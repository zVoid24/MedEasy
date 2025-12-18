package api

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/golang-jwt/jwt/v5"
	"github.com/jmoiron/sqlx"
	"golang.org/x/crypto/bcrypt"

	"medeasy/m/domain"
)

type ctxKey string

const (
	ctxUserID ctxKey = "userID"
	ctxRole   ctxKey = "role"
)

// Handler bundles dependencies for HTTP handlers.
type Handler struct {
	db     *sqlx.DB
	secret string
}

// New constructs a Handler.
func New(db *sqlx.DB, secret string) *Handler {
	return &Handler{db: db, secret: secret}
}

// Router wires up the HTTP API.
func (h *Handler) Router() http.Handler {
	r := chi.NewRouter()
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)

	r.Get("/health", h.health)

	r.Route("/auth", func(r chi.Router) {
		r.Post("/register", h.register)
		r.Post("/login", h.login)
		r.Group(func(protected chi.Router) {
			protected.Use(h.authMiddleware)
			protected.Post("/reset-password", h.resetPassword)
		})
	})

	r.Group(func(pr chi.Router) {
		pr.Use(h.authMiddleware)

		pr.Route("/pharmacies", func(r chi.Router) {
			r.Post("/", h.createPharmacy)
			r.Get("/", h.listPharmacies)
			r.Put("/{id}", h.updatePharmacy)
		})

		pr.Get("/medicines", h.searchMedicines)

		pr.Route("/inventory", func(r chi.Router) {
			r.Post("/", h.addInventory)
			r.Put("/{id}", h.updateInventory)
			r.Post("/{id}/stock", h.updateStock)
			r.Get("/search", h.searchInventoryMedicines)
			r.Get("/expiry-alert", h.expiryAlerts)
		})

		pr.Route("/sales", func(r chi.Router) {
			r.Post("/", h.createSale)
		})

		pr.Route("/reports", func(r chi.Router) {
			r.Get("/sales/daily", h.dailySales)
			r.Get("/sales/monthly", h.monthlySales)
			r.Get("/sales", h.salesReport)
		})
	})

	return r
}

func (h *Handler) health(w http.ResponseWriter, r *http.Request) {
	respondJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// Authentication helpers

type authClaims struct {
	UserID int64  `json:"user_id"`
	Role   string `json:"role"`
	jwt.RegisteredClaims
}

func (h *Handler) generateToken(userID int64, role string) (string, error) {
	claims := authClaims{
		UserID: userID,
		Role:   role,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(24 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(h.secret))
}

func (h *Handler) authMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		header := r.Header.Get("Authorization")
		if header == "" || !strings.HasPrefix(strings.ToLower(header), "bearer ") {
			respondError(w, http.StatusUnauthorized, "missing bearer token")
			return
		}
		tokenString := strings.TrimSpace(header[len("Bearer "):])
		token, err := jwt.ParseWithClaims(tokenString, &authClaims{}, func(token *jwt.Token) (interface{}, error) {
			if token.Method != jwt.SigningMethodHS256 {
				return nil, errors.New("unexpected signing method")
			}
			return []byte(h.secret), nil
		})
		if err != nil || !token.Valid {
			respondError(w, http.StatusUnauthorized, "invalid token")
			return
		}
		claims, ok := token.Claims.(*authClaims)
		if !ok {
			respondError(w, http.StatusUnauthorized, "invalid token claims")
			return
		}
		ctx := context.WithValue(r.Context(), ctxUserID, claims.UserID)
		ctx = context.WithValue(ctx, ctxRole, claims.Role)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func (h *Handler) requireRole(w http.ResponseWriter, r *http.Request, allowed ...string) bool {
	role := r.Context().Value(ctxRole)
	if role == nil {
		respondError(w, http.StatusUnauthorized, "missing role")
		return false
	}
	current := role.(string)
	for _, allowedRole := range allowed {
		if current == allowedRole {
			return true
		}
	}
	respondError(w, http.StatusForbidden, "insufficient permissions")
	return false
}

// Auth Handlers

type registerRequest struct {
	Username         string `json:"username"`
	Email            string `json:"email"`
	Password         string `json:"password"`
	Role             string `json:"role"`
	PharmacyName     string `json:"pharmacy_name,omitempty"`
	PharmacyAddress  string `json:"pharmacy_address,omitempty"`
	PharmacyLocation string `json:"pharmacy_location,omitempty"`
}

type authResponse struct {
	Token    string           `json:"token"`
	User     domain.User      `json:"user"`
	Pharmacy *domain.Pharmacy `json:"pharmacy,omitempty"`
}

func (h *Handler) register(w http.ResponseWriter, r *http.Request) {
	var req registerRequest
	if err := decodeJSON(r, &req); err != nil {
		respondError(w, http.StatusBadRequest, err.Error())
		return
	}
	if req.Username == "" || req.Email == "" || req.Password == "" || req.Role == "" {
		respondError(w, http.StatusBadRequest, "username, email, password and role are required")
		return
	}

	if req.Role != "owner" && req.Role != "employee" {
		respondError(w, http.StatusBadRequest, "role must be owner or employee")
		return
	}

	if req.Role == "owner" && strings.TrimSpace(req.PharmacyName) == "" {
		respondError(w, http.StatusBadRequest, "pharmacy_name is required for owners")
		return
	}

	hashed, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "unable to secure password")
		return
	}

	tx, err := h.db.Beginx()
	if err != nil {
		respondError(w, http.StatusInternalServerError, "unable to start registration")
		return
	}

	var userID int64
	err = tx.QueryRowx(`INSERT INTO users (username, email, password, role) VALUES ($1, $2, $3, $4) RETURNING id`, req.Username, strings.ToLower(req.Email), hashed, req.Role).Scan(&userID)
	if err != nil {
		_ = tx.Rollback()
		respondError(w, http.StatusConflict, "email already exists")
		return
	}

	var pharmacy *domain.Pharmacy
	if req.Role == "owner" {
		var (
			pharmacyID int64
			createdAt  string
		)
		err = tx.QueryRowx(`INSERT INTO pharmacies (name, address, location, owner_id) VALUES ($1, $2, $3, $4) RETURNING id, created_at`,
			req.PharmacyName, req.PharmacyAddress, req.PharmacyLocation, userID).Scan(&pharmacyID, &createdAt)
		if err != nil {
			_ = tx.Rollback()
			respondError(w, http.StatusInternalServerError, "unable to create pharmacy for owner")
			return
		}
		pharmacy = &domain.Pharmacy{
			ID:        pharmacyID,
			Name:      req.PharmacyName,
			Address:   req.PharmacyAddress,
			Location:  req.PharmacyLocation,
			OwnerID:   &userID,
			CreatedAt: createdAt,
		}
	}

	if err := tx.Commit(); err != nil {
		respondError(w, http.StatusInternalServerError, "unable to complete registration")
		return
	}

	token, err := h.generateToken(userID, req.Role)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "unable to generate token")
		return
	}

	respondJSON(w, http.StatusCreated, authResponse{Token: token, User: domain.User{ID: int(userID), Username: req.Username, Email: strings.ToLower(req.Email), Role: req.Role}, Pharmacy: pharmacy})
}

type loginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

func (h *Handler) login(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
	if err := decodeJSON(r, &req); err != nil {
		respondError(w, http.StatusBadRequest, err.Error())
		return
	}

	var user domain.User
	err := h.db.Get(&user, `SELECT id, username, email, password, role FROM users WHERE email = $1`, strings.ToLower(req.Email))
	if err != nil {
		respondError(w, http.StatusUnauthorized, "invalid credentials")
		return
	}

	if bcrypt.CompareHashAndPassword([]byte(user.Password), []byte(req.Password)) != nil {
		respondError(w, http.StatusUnauthorized, "invalid credentials")
		return
	}

	token, err := h.generateToken(int64(user.ID), user.Role)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "unable to generate token")
		return
	}

	user.Password = ""
	respondJSON(w, http.StatusOK, authResponse{Token: token, User: user})
}

func (h *Handler) resetPassword(w http.ResponseWriter, r *http.Request) {
	var payload struct {
		NewPassword string `json:"new_password"`
	}
	if err := decodeJSON(r, &payload); err != nil {
		respondError(w, http.StatusBadRequest, err.Error())
		return
	}
	if payload.NewPassword == "" {
		respondError(w, http.StatusBadRequest, "new_password is required")
		return
	}
	uid := r.Context().Value(ctxUserID).(int64)
	hashed, err := bcrypt.GenerateFromPassword([]byte(payload.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "unable to secure password")
		return
	}
	if _, err := h.db.Exec(`UPDATE users SET password = $1 WHERE id = $2`, hashed, uid); err != nil {
		respondError(w, http.StatusInternalServerError, "unable to update password")
		return
	}
	respondJSON(w, http.StatusOK, map[string]string{"status": "password updated"})
}

// Pharmacy handlers

type pharmacyRequest struct {
	Name     string `json:"name"`
	Address  string `json:"address"`
	Location string `json:"location"`
}

func (h *Handler) createPharmacy(w http.ResponseWriter, r *http.Request) {
	if !h.requireRole(w, r, "owner") {
		return
	}
	var req pharmacyRequest
	if err := decodeJSON(r, &req); err != nil {
		respondError(w, http.StatusBadRequest, err.Error())
		return
	}
	if req.Name == "" {
		respondError(w, http.StatusBadRequest, "name is required")
		return
	}
	ownerID := r.Context().Value(ctxUserID).(int64)
	var id int64
	err := h.db.QueryRowx(`INSERT INTO pharmacies (name, address, location, owner_id) VALUES ($1, $2, $3, $4) RETURNING id`, req.Name, req.Address, req.Location, ownerID).Scan(&id)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "unable to create pharmacy")
		return
	}
	respondJSON(w, http.StatusCreated, map[string]any{"id": id, "name": req.Name})
}

func (h *Handler) updatePharmacy(w http.ResponseWriter, r *http.Request) {
	if !h.requireRole(w, r, "owner") {
		return
	}
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		respondError(w, http.StatusBadRequest, "invalid pharmacy id")
		return
	}
	var req pharmacyRequest
	if err := decodeJSON(r, &req); err != nil {
		respondError(w, http.StatusBadRequest, err.Error())
		return
	}
	if req.Name == "" {
		respondError(w, http.StatusBadRequest, "name is required")
		return
	}
	if _, err := h.db.Exec(`UPDATE pharmacies SET name = $1, address = $2, location = $3 WHERE id = $4`, req.Name, req.Address, req.Location, id); err != nil {
		respondError(w, http.StatusInternalServerError, "unable to update pharmacy")
		return
	}
	respondJSON(w, http.StatusOK, map[string]string{"status": "updated"})
}

func (h *Handler) listPharmacies(w http.ResponseWriter, r *http.Request) {
	var pharmacies []domain.Pharmacy
	if err := h.db.Select(&pharmacies, `SELECT id, name, address, location, owner_id, created_at FROM pharmacies`); err != nil {
		respondError(w, http.StatusInternalServerError, "unable to list pharmacies")
		return
	}
	respondJSON(w, http.StatusOK, pharmacies)
}

// Medicine search
func (h *Handler) searchMedicines(w http.ResponseWriter, r *http.Request) {
	query := strings.TrimSpace(r.URL.Query().Get("query"))
	var medicines []domain.Medicine
	if query == "" {
		h.db.Select(&medicines, `SELECT id, brand_id, brand_name, type, generic_name, manufacturer FROM medicines ORDER BY brand_name LIMIT 25`)
	} else {
		like := "%" + query + "%"
		h.db.Select(&medicines, `SELECT id, brand_id, brand_name, type, generic_name, manufacturer FROM medicines WHERE brand_name ILIKE $1 OR generic_name ILIKE $2 ORDER BY brand_name LIMIT 25`, like, like)
	}
	respondJSON(w, http.StatusOK, medicines)
}

type inventorySearchResult struct {
	InventoryID  int64   `db:"inventory_id" json:"inventory_id"`
	MedicineID   int64   `db:"medicine_id" json:"medicine_id"`
	BrandName    string  `db:"brand_name" json:"brand_name"`
	GenericName  string  `db:"generic_name" json:"generic_name"`
	Manufacturer string  `db:"manufacturer" json:"manufacturer"`
	Type         string  `db:"type" json:"type"`
	Quantity     int64   `db:"quantity" json:"quantity"`
	UnitCost     float64 `db:"cost_price" json:"unit_cost"`
	UnitPrice    float64 `db:"sale_price" json:"unit_price"`
	TotalCost    float64 `db:"total_cost" json:"total_cost"`
}

func (h *Handler) searchInventoryMedicines(w http.ResponseWriter, r *http.Request) {
	if !h.requireRole(w, r, "owner", "employee") {
		return
	}
	pharmacyID, err := strconv.ParseInt(r.URL.Query().Get("pharmacy_id"), 10, 64)
	if err != nil || pharmacyID <= 0 {
		respondError(w, http.StatusBadRequest, "valid pharmacy_id is required")
		return
	}
	query := strings.TrimSpace(r.URL.Query().Get("query"))
	args := []any{pharmacyID}
	sqlQuery := `SELECT i.id AS inventory_id, i.medicine_id, i.quantity, i.cost_price, i.sale_price, m.brand_name, m.generic_name, m.manufacturer, m.type, (i.cost_price * i.quantity) AS total_cost
                FROM inventory i
                JOIN medicines m ON m.id = i.medicine_id
                WHERE i.pharmacy_id = $1 AND i.quantity > 0`
	if query != "" {
		like := "%" + query + "%"
		args = append(args, like)
		sqlQuery += " AND (m.brand_name ILIKE $2 OR m.generic_name ILIKE $2)"
	}
	sqlQuery += " ORDER BY m.brand_name LIMIT 25"

	var results []inventorySearchResult
	if err := h.db.Select(&results, sqlQuery, args...); err != nil {
		respondError(w, http.StatusInternalServerError, "unable to search inventory")
		return
	}
	respondJSON(w, http.StatusOK, results)
}

// Inventory handlers

type inventoryRequest struct {
	PharmacyID int64   `json:"pharmacy_id"`
	MedicineID int64   `json:"medicine_id"`
	Quantity   int64   `json:"quantity"`
	CostPrice  float64 `json:"cost_price"`
	SalePrice  float64 `json:"sale_price"`
	ExpiryDate string  `json:"expiry_date"`
}

func (h *Handler) addInventory(w http.ResponseWriter, r *http.Request) {
	if !h.requireRole(w, r, "owner", "employee") {
		return
	}
	var req inventoryRequest
	if err := decodeJSON(r, &req); err != nil {
		respondError(w, http.StatusBadRequest, err.Error())
		return
	}
	if req.PharmacyID == 0 || req.MedicineID == 0 || req.Quantity <= 0 || req.CostPrice <= 0 || req.SalePrice <= 0 {
		respondError(w, http.StatusBadRequest, "pharmacy_id, medicine_id, quantity, cost_price and sale_price are required")
		return
	}
	unitCost := req.CostPrice / float64(req.Quantity)
	unitSale := req.SalePrice / float64(req.Quantity)
	_, err := h.db.Exec(`INSERT INTO inventory (pharmacy_id, medicine_id, quantity, cost_price, sale_price, expiry_date) VALUES ($1, $2, $3, $4, $5, $6)`,
		req.PharmacyID, req.MedicineID, req.Quantity, unitCost, unitSale, nullIfEmpty(req.ExpiryDate))
	if err != nil {
		respondError(w, http.StatusInternalServerError, "unable to add inventory")
		return
	}
	respondJSON(w, http.StatusCreated, map[string]any{
		"status":          "inventory added",
		"unit_cost_price": unitCost,
		"unit_sale_price": unitSale,
	})
}

func (h *Handler) updateInventory(w http.ResponseWriter, r *http.Request) {
	if !h.requireRole(w, r, "owner", "employee") {
		return
	}
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		respondError(w, http.StatusBadRequest, "invalid inventory id")
		return
	}
	var req inventoryRequest
	if err := decodeJSON(r, &req); err != nil {
		respondError(w, http.StatusBadRequest, err.Error())
		return
	}
	if req.Quantity < 0 || req.CostPrice <= 0 || req.SalePrice <= 0 {
		respondError(w, http.StatusBadRequest, "quantity, cost_price and sale_price are required")
		return
	}
	if req.Quantity == 0 {
		respondError(w, http.StatusBadRequest, "quantity must be greater than zero")
		return
	}
	unitCost := req.CostPrice / float64(req.Quantity)
	unitSale := req.SalePrice / float64(req.Quantity)
	_, err = h.db.Exec(`UPDATE inventory SET pharmacy_id = $1, medicine_id = $2, quantity = $3, cost_price = $4, sale_price = $5, expiry_date = $6, updated_at = CURRENT_TIMESTAMP WHERE id = $7`,
		req.PharmacyID, req.MedicineID, req.Quantity, unitCost, unitSale, nullIfEmpty(req.ExpiryDate), id)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "unable to update inventory")
		return
	}
	respondJSON(w, http.StatusOK, map[string]any{
		"status":          "updated",
		"unit_cost_price": unitCost,
		"unit_sale_price": unitSale,
	})
}

func (h *Handler) updateStock(w http.ResponseWriter, r *http.Request) {
	if !h.requireRole(w, r, "owner", "employee") {
		return
	}
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		respondError(w, http.StatusBadRequest, "invalid inventory id")
		return
	}
	var payload struct {
		Quantity int64 `json:"quantity"`
	}
	if err := decodeJSON(r, &payload); err != nil {
		respondError(w, http.StatusBadRequest, err.Error())
		return
	}
	if payload.Quantity < 0 {
		respondError(w, http.StatusBadRequest, "quantity must be positive")
		return
	}
	_, err = h.db.Exec(`UPDATE inventory SET quantity = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2`, payload.Quantity, id)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "unable to update stock")
		return
	}
	respondJSON(w, http.StatusOK, map[string]string{"status": "stock updated"})
}

func (h *Handler) expiryAlerts(w http.ResponseWriter, r *http.Request) {
	days, _ := strconv.Atoi(r.URL.Query().Get("days"))
	if days <= 0 {
		days = 30
	}
	var items []domain.InventoryItem
	if err := h.db.Select(&items, `SELECT id, pharmacy_id, medicine_id, quantity, cost_price, sale_price, expiry_date, created_at, updated_at FROM inventory
                WHERE expiry_date IS NOT NULL
                AND expiry_date <= (CURRENT_DATE + ($1 * INTERVAL '1 day'))
                ORDER BY expiry_date ASC`, days); err != nil {
		respondError(w, http.StatusInternalServerError, "unable to fetch alerts")
		return
	}
	respondJSON(w, http.StatusOK, items)
}

// Sales handlers

type saleItemRequest struct {
	MedicineID int64 `json:"medicine_id"`
	Quantity   int64 `json:"quantity"`
}

type saleRequest struct {
	PharmacyID int64             `json:"pharmacy_id"`
	Items      []saleItemRequest `json:"items"`
	Discount   float64           `json:"discount"`
	PaidAmount float64           `json:"paid_amount"`
}

func (h *Handler) createSale(w http.ResponseWriter, r *http.Request) {
	if !h.requireRole(w, r, "owner", "employee") {
		return
	}
	var req saleRequest
	if err := decodeJSON(r, &req); err != nil {
		respondError(w, http.StatusBadRequest, err.Error())
		return
	}
	if req.PharmacyID == 0 || len(req.Items) == 0 {
		respondError(w, http.StatusBadRequest, "pharmacy_id and at least one item are required")
		return
	}

	type inventorySnapshot struct {
		ID        int64   `db:"id"`
		SalePrice float64 `db:"sale_price"`
		Quantity  int64   `db:"quantity"`
	}

	snapshots := make(map[int64]inventorySnapshot)
	var total float64

	for _, item := range req.Items {
		if item.MedicineID == 0 || item.Quantity <= 0 {
			respondError(w, http.StatusBadRequest, "medicine_id and quantity are required for each item")
			return
		}
		var snap inventorySnapshot
		err := h.db.Get(&snap, `SELECT id, sale_price, quantity FROM inventory WHERE pharmacy_id = $1 AND medicine_id = $2 ORDER BY COALESCE(expiry_date, CURRENT_DATE) ASC LIMIT 1`, req.PharmacyID, item.MedicineID)
		if errors.Is(err, sql.ErrNoRows) {
			respondError(w, http.StatusBadRequest, "inventory not found for one or more items")
			return
		}
		if err != nil {
			respondError(w, http.StatusInternalServerError, "unable to fetch inventory")
			return
		}
		if snap.Quantity < item.Quantity {
			respondError(w, http.StatusBadRequest, "insufficient stock for one or more items")
			return
		}
		snapshots[item.MedicineID] = snap
		total += float64(item.Quantity) * snap.SalePrice
	}

	totalAfterDiscount := total - req.Discount
	if totalAfterDiscount < 0 {
		totalAfterDiscount = 0
	}
	due := totalAfterDiscount - req.PaidAmount
	if due < 0 {
		due = 0
	}

	tx, err := h.db.Beginx()
	if err != nil {
		respondError(w, http.StatusInternalServerError, "unable to start sale")
		return
	}
	defer tx.Rollback()

	userID := r.Context().Value(ctxUserID).(int64)
	var saleID int64
	err = tx.QueryRowx(`INSERT INTO sales (pharmacy_id, user_id, total_amount, discount, paid_amount, due_amount) VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`,
		req.PharmacyID, userID, total, req.Discount, req.PaidAmount, due).Scan(&saleID)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "unable to create sale")
		return
	}

	for _, item := range req.Items {
		snap := snapshots[item.MedicineID]
		newQty := snap.Quantity - item.Quantity
		if _, err := tx.Exec(`UPDATE inventory SET quantity = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2`, newQty, snap.ID); err != nil {
			respondError(w, http.StatusInternalServerError, "unable to update inventory")
			return
		}
		subtotal := float64(item.Quantity) * snap.SalePrice
		if _, err := tx.Exec(`INSERT INTO sale_items (sale_id, medicine_id, quantity, unit_price, subtotal) VALUES ($1, $2, $3, $4, $5)`,
			saleID, item.MedicineID, item.Quantity, snap.SalePrice, subtotal); err != nil {
			respondError(w, http.StatusInternalServerError, "unable to save sale items")
			return
		}
	}

	if err := tx.Commit(); err != nil {
		respondError(w, http.StatusInternalServerError, "unable to finalize sale")
		return
	}

	respondJSON(w, http.StatusCreated, map[string]any{
		"sale_id":      saleID,
		"total":        total,
		"discount":     req.Discount,
		"paid_amount":  req.PaidAmount,
		"due_amount":   due,
		"final_amount": totalAfterDiscount,
	})
}

// Reports
func (h *Handler) dailySales(w http.ResponseWriter, r *http.Request) {
	pharmacyID := r.URL.Query().Get("pharmacy_id")
	query := `SELECT COALESCE(SUM(total_amount - discount),0) AS revenue, COUNT(*) AS count FROM sales WHERE DATE(created_at) = CURRENT_DATE`
	args := []interface{}{}
	if pharmacyID != "" {
		query += " AND pharmacy_id = $1"
		args = append(args, pharmacyID)
	}
	var revenue float64
	var count int64
	err := h.db.QueryRow(query, args...).Scan(&revenue, &count)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "unable to fetch daily sales")
		return
	}
	respondJSON(w, http.StatusOK, map[string]any{"revenue": revenue, "sales_count": count})
}

func (h *Handler) monthlySales(w http.ResponseWriter, r *http.Request) {
	pharmacyID := r.URL.Query().Get("pharmacy_id")
	query := `SELECT COALESCE(SUM(total_amount - discount),0) AS revenue, COUNT(*) AS count FROM sales WHERE DATE(created_at) >= date_trunc('month', CURRENT_DATE)`
	args := []interface{}{}
	if pharmacyID != "" {
		query += " AND pharmacy_id = $1"
		args = append(args, pharmacyID)
	}
	var revenue float64
	var count int64
	err := h.db.QueryRow(query, args...).Scan(&revenue, &count)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "unable to fetch monthly sales")
		return
	}
	respondJSON(w, http.StatusOK, map[string]any{"revenue": revenue, "sales_count": count})
}

type saleItemDetail struct {
	SaleID     int64   `db:"sale_id" json:"sale_id"`
	MedicineID int64   `db:"medicine_id" json:"medicine_id"`
	BrandName  string  `db:"brand_name" json:"brand_name"`
	Quantity   int64   `db:"quantity" json:"quantity"`
	UnitPrice  float64 `db:"unit_price" json:"unit_price"`
	Subtotal   float64 `db:"subtotal" json:"subtotal"`
}

type saleReportEntry struct {
	domain.Sale
	Items []saleItemDetail `json:"items"`
}

func (h *Handler) salesReport(w http.ResponseWriter, r *http.Request) {
	if !h.requireRole(w, r, "owner") {
		return
	}

	var (
		args    []any
		clauses []string
	)

	pharmacyIDStr := strings.TrimSpace(r.URL.Query().Get("pharmacy_id"))
	if pharmacyIDStr != "" {
		pharmacyID, err := strconv.ParseInt(pharmacyIDStr, 10, 64)
		if err != nil || pharmacyID <= 0 {
			respondError(w, http.StatusBadRequest, "invalid pharmacy_id")
			return
		}
		args = append(args, pharmacyID)
		clauses = append(clauses, fmt.Sprintf("pharmacy_id = $%d", len(args)))
	}

	startDate := strings.TrimSpace(r.URL.Query().Get("start_date"))
	if startDate != "" {
		if _, err := time.Parse("2006-01-02", startDate); err != nil {
			respondError(w, http.StatusBadRequest, "start_date must be in YYYY-MM-DD format")
			return
		}
		args = append(args, startDate)
		clauses = append(clauses, fmt.Sprintf("DATE(created_at) >= $%d", len(args)))
	}

	endDate := strings.TrimSpace(r.URL.Query().Get("end_date"))
	if endDate != "" {
		if _, err := time.Parse("2006-01-02", endDate); err != nil {
			respondError(w, http.StatusBadRequest, "end_date must be in YYYY-MM-DD format")
			return
		}
		args = append(args, endDate)
		clauses = append(clauses, fmt.Sprintf("DATE(created_at) <= $%d", len(args)))
	}

	query := `SELECT id, pharmacy_id, user_id, total_amount, discount, paid_amount, due_amount, created_at FROM sales`
	if len(clauses) > 0 {
		query += " WHERE " + strings.Join(clauses, " AND ")
	}
	query += " ORDER BY created_at DESC"

	var sales []domain.Sale
	if err := h.db.Select(&sales, query, args...); err != nil {
		respondError(w, http.StatusInternalServerError, "unable to fetch sales report")
		return
	}
	if len(sales) == 0 {
		respondJSON(w, http.StatusOK, []saleReportEntry{})
		return
	}

	ids := make([]int64, len(sales))
	for i, sale := range sales {
		ids[i] = sale.ID
	}

	itemsQuery, itemsArgs, err := sqlx.In(`SELECT si.sale_id, si.medicine_id, si.quantity, si.unit_price, si.subtotal, m.brand_name
                FROM sale_items si
                JOIN medicines m ON m.id = si.medicine_id
                WHERE si.sale_id IN (?)`, ids)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "unable to prepare sale items query")
		return
	}
	itemsQuery = h.db.Rebind(itemsQuery)

	var rows []saleItemDetail
	if err := h.db.Select(&rows, itemsQuery, itemsArgs...); err != nil {
		respondError(w, http.StatusInternalServerError, "unable to load sale items")
		return
	}
	itemsBySale := make(map[int64][]saleItemDetail)
	for _, row := range rows {
		itemsBySale[row.SaleID] = append(itemsBySale[row.SaleID], row)
	}

	report := make([]saleReportEntry, len(sales))
	for i, sale := range sales {
		report[i] = saleReportEntry{Sale: sale, Items: itemsBySale[sale.ID]}
	}

	respondJSON(w, http.StatusOK, report)
}

// Helpers
func nullIfEmpty(val string) *string {
	trimmed := strings.TrimSpace(val)
	if trimmed == "" {
		return nil
	}
	return &trimmed
}

func decodeJSON(r *http.Request, dest interface{}) error {
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	return decoder.Decode(dest)
}

func respondJSON(w http.ResponseWriter, status int, payload interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	encoder := json.NewEncoder(w)
	encoder.SetEscapeHTML(false)
	_ = encoder.Encode(payload)
}

func respondError(w http.ResponseWriter, status int, message string) {
	respondJSON(w, status, map[string]string{"error": message})
}
