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
	"github.com/go-chi/cors"
	"github.com/golang-jwt/jwt/v5"
	"github.com/jmoiron/sqlx"
	"golang.org/x/crypto/bcrypt"

	"medeasy/m/domain"
)

type ctxKey string

const (
	ctxUserID     ctxKey = "userID"
	ctxRole       ctxKey = "role"
	ctxPharmacyID ctxKey = "pharmacyID"
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
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   []string{"*"}, // Change "*" to a list of allowed domains (e.g., ["http://localhost:3000"])
		AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Content-Type", "Authorization"},
		AllowCredentials: true,
	}))
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
	UserID     int64  `json:"user_id"`
	Role       string `json:"role"`
	PharmacyID int64  `json:"pharmacy_id"`
	jwt.RegisteredClaims
}

func (h *Handler) generateToken(userID int64, role string, pharmacyID int64) (string, error) {
	claims := authClaims{
		UserID:     userID,
		Role:       role,
		PharmacyID: pharmacyID,
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
		if claims.PharmacyID <= 0 {
			respondError(w, http.StatusForbidden, "user is not linked to a pharmacy")
			return
		}
		ctx = context.WithValue(ctx, ctxPharmacyID, claims.PharmacyID)
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

func pharmacyIDFromContext(r *http.Request) int64 {
	if val := r.Context().Value(ctxPharmacyID); val != nil {
		if id, ok := val.(int64); ok {
			return id
		}
	}
	return 0
}

// Auth Handlers

type registerRequest struct {
	Username         string `json:"username"`
	Email            string `json:"email"`
	Password         string `json:"password"`
	Role             string `json:"role"`
	PharmacyID       int64  `json:"pharmacy_id,omitempty"`
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
	if req.Role == "employee" && req.PharmacyID <= 0 {
		respondError(w, http.StatusBadRequest, "pharmacy_id is required for employees")
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

	if req.Role == "employee" {
		var exists bool
		if err := tx.Get(&exists, `SELECT EXISTS(SELECT 1 FROM pharmacies WHERE id = $1)`, req.PharmacyID); err != nil || !exists {
			_ = tx.Rollback()
			respondError(w, http.StatusBadRequest, "invalid pharmacy_id for employee")
			return
		}
	}

	var (
		userID           int64
		assignedPharmacy int64
	)
	pharmacyIDValue := sql.NullInt64{}
	if req.Role == "employee" {
		pharmacyIDValue = sql.NullInt64{Int64: req.PharmacyID, Valid: true}
	}

	err = tx.QueryRowx(`INSERT INTO users (username, email, password, role, pharmacy_id) VALUES ($1, $2, $3, $4, $5) RETURNING id`, req.Username, strings.ToLower(req.Email), hashed, req.Role, pharmacyIDValue).Scan(&userID)
	if err != nil {
		_ = tx.Rollback()
		if strings.Contains(err.Error(), "unique constraint") || strings.Contains(err.Error(), "duplicate key") {
			respondError(w, http.StatusConflict, "email already exists")
		} else {
			respondError(w, http.StatusInternalServerError, "db error: "+err.Error())
		}
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
		if _, err := tx.Exec(`UPDATE users SET pharmacy_id = $1 WHERE id = $2`, pharmacyID, userID); err != nil {
			_ = tx.Rollback()
			respondError(w, http.StatusInternalServerError, "unable to link owner to pharmacy")
			return
		}
		assignedPharmacy = pharmacyID
		pharmacy = &domain.Pharmacy{
			ID:        pharmacyID,
			Name:      req.PharmacyName,
			Address:   req.PharmacyAddress,
			Location:  req.PharmacyLocation,
			OwnerID:   &userID,
			CreatedAt: createdAt,
		}
	} else {
		assignedPharmacy = req.PharmacyID
	}

	if err := tx.Commit(); err != nil {
		respondError(w, http.StatusInternalServerError, "unable to complete registration")
		return
	}

	token, err := h.generateToken(userID, req.Role, assignedPharmacy)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "unable to generate token")
		return
	}

	respondJSON(w, http.StatusCreated, authResponse{Token: token, User: domain.User{ID: int(userID), Username: req.Username, Email: strings.ToLower(req.Email), Role: req.Role, PharmacyID: &assignedPharmacy}, Pharmacy: pharmacy})
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
	err := h.db.Get(&user, `SELECT id, username, email, password, role, pharmacy_id FROM users WHERE email = $1`, strings.ToLower(req.Email))
	if err != nil {
		respondError(w, http.StatusUnauthorized, "invalid credentials")
		return
	}

	if bcrypt.CompareHashAndPassword([]byte(user.Password), []byte(req.Password)) != nil {
		respondError(w, http.StatusUnauthorized, "invalid credentials")
		return
	}

	if user.PharmacyID == nil || *user.PharmacyID == 0 {
		respondError(w, http.StatusForbidden, "user is not linked to a pharmacy")
		return
	}

	token, err := h.generateToken(int64(user.ID), user.Role, *user.PharmacyID)
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
	ExpiryDate   *string `db:"expiry_date" json:"expiry_date"`
}

func (h *Handler) searchInventoryMedicines(w http.ResponseWriter, r *http.Request) {
	if !h.requireRole(w, r, "owner", "employee") {
		return
	}
	pharmacyID := pharmacyIDFromContext(r)
	if pharmacyID <= 0 {
		respondError(w, http.StatusForbidden, "invalid pharmacy context")
		return
	}
	query := strings.TrimSpace(r.URL.Query().Get("query"))
	args := []any{pharmacyID}
	sqlQuery := `SELECT i.id AS inventory_id, i.medicine_id, i.quantity, i.cost_price, i.sale_price, i.expiry_date, m.brand_name, m.generic_name, m.manufacturer, m.type, (i.cost_price * i.quantity) AS total_cost
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
	pharmacyID := pharmacyIDFromContext(r)
	if pharmacyID <= 0 {
		respondError(w, http.StatusForbidden, "invalid pharmacy context")
		return
	}
	var req inventoryRequest
	if err := decodeJSON(r, &req); err != nil {
		respondError(w, http.StatusBadRequest, err.Error())
		return
	}
	if req.MedicineID == 0 || req.Quantity <= 0 || req.CostPrice <= 0 || req.SalePrice <= 0 {
		respondError(w, http.StatusBadRequest, "medicine_id, quantity, cost_price and sale_price are required")
		return
	}
	unitCost := req.CostPrice / float64(req.Quantity)
	unitSale := req.SalePrice / float64(req.Quantity)
	_, err := h.db.Exec(`INSERT INTO inventory (pharmacy_id, medicine_id, quantity, cost_price, sale_price, expiry_date) VALUES ($1, $2, $3, $4, $5, $6)`,
		pharmacyID, req.MedicineID, req.Quantity, unitCost, unitSale, nullIfEmpty(req.ExpiryDate))
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
	pharmacyID := pharmacyIDFromContext(r)
	if pharmacyID <= 0 {
		respondError(w, http.StatusForbidden, "invalid pharmacy context")
		return
	}
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		respondError(w, http.StatusBadRequest, "invalid inventory id")
		return
	}
	var existingPharmacyID int64
	if err := h.db.Get(&existingPharmacyID, `SELECT pharmacy_id FROM inventory WHERE id = $1`, id); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			respondError(w, http.StatusNotFound, "inventory not found")
			return
		}
		respondError(w, http.StatusInternalServerError, "unable to load inventory")
		return
	}
	if existingPharmacyID != pharmacyID {
		respondError(w, http.StatusForbidden, "inventory does not belong to your pharmacy")
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
	_, err = h.db.Exec(`UPDATE inventory SET medicine_id = $1, quantity = $2, cost_price = $3, sale_price = $4, expiry_date = $5, updated_at = CURRENT_TIMESTAMP WHERE id = $6`,
		req.MedicineID, req.Quantity, unitCost, unitSale, nullIfEmpty(req.ExpiryDate), id)
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
	pharmacyID := pharmacyIDFromContext(r)
	if pharmacyID <= 0 {
		respondError(w, http.StatusForbidden, "invalid pharmacy context")
		return
	}
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		respondError(w, http.StatusBadRequest, "invalid inventory id")
		return
	}
	var existingPharmacyID int64
	if err := h.db.Get(&existingPharmacyID, `SELECT pharmacy_id FROM inventory WHERE id = $1`, id); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			respondError(w, http.StatusNotFound, "inventory not found")
			return
		}
		respondError(w, http.StatusInternalServerError, "unable to load inventory")
		return
	}
	if existingPharmacyID != pharmacyID {
		respondError(w, http.StatusForbidden, "inventory does not belong to your pharmacy")
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
	pharmacyID := pharmacyIDFromContext(r)
	if pharmacyID <= 0 {
		respondError(w, http.StatusForbidden, "invalid pharmacy context")
		return
	}
	days, _ := strconv.Atoi(r.URL.Query().Get("days"))
	if days <= 0 {
		days = 30
	}
	var items []domain.InventoryItem
	if err := h.db.Select(&items, `SELECT id, pharmacy_id, medicine_id, quantity, cost_price, sale_price, expiry_date, created_at, updated_at FROM inventory
                WHERE expiry_date IS NOT NULL
                AND pharmacy_id = $2
                AND expiry_date <= (CURRENT_DATE + ($1 * INTERVAL '1 day'))
                ORDER BY expiry_date ASC`, days, pharmacyID); err != nil {
		respondError(w, http.StatusInternalServerError, "unable to fetch alerts")
		return
	}
	respondJSON(w, http.StatusOK, items)
}

// Sales handlers

type saleItemRequest struct {
	InventoryID int64 `json:"inventory_id"`
	MedicineID  int64 `json:"medicine_id"`
	Quantity    int64 `json:"quantity"`
}

type saleRequest struct {
	Items      []saleItemRequest `json:"items"`
	Discount   float64           `json:"discount"`
	PaidAmount float64           `json:"paid_amount"`
}

func (h *Handler) createSale(w http.ResponseWriter, r *http.Request) {
	if !h.requireRole(w, r, "owner", "employee") {
		return
	}
	pharmacyID := pharmacyIDFromContext(r)
	if pharmacyID <= 0 {
		respondError(w, http.StatusForbidden, "invalid pharmacy context")
		return
	}
	var req saleRequest
	if err := decodeJSON(r, &req); err != nil {
		respondError(w, http.StatusBadRequest, err.Error())
		return
	}
	if len(req.Items) == 0 {
		respondError(w, http.StatusBadRequest, "at least one item is required")
		return
	}

	type inventorySnapshot struct {
		ID         int64   `db:"id"`
		MedicineID int64   `db:"medicine_id"`
		SalePrice  float64 `db:"sale_price"`
		Quantity   int64   `db:"quantity"`
	}

	snapshots := make(map[int64]inventorySnapshot)
	remaining := make(map[int64]int64)
	var total float64

	for _, item := range req.Items {
		if item.InventoryID <= 0 || item.Quantity <= 0 {
			respondError(w, http.StatusBadRequest, "inventory_id and quantity are required for each item")
			return
		}
		snap, ok := snapshots[item.InventoryID]
		if !ok {
			err := h.db.Get(&snap, `SELECT id, medicine_id, sale_price, quantity FROM inventory WHERE id = $1 AND pharmacy_id = $2`, item.InventoryID, pharmacyID)
			if errors.Is(err, sql.ErrNoRows) {
				respondError(w, http.StatusBadRequest, fmt.Sprintf("inventory not found for item %d (user pharmacy_id: %d)", item.InventoryID, pharmacyID))
				return
			}
			if err != nil {
				respondError(w, http.StatusInternalServerError, "unable to fetch inventory")
				return
			}
			snapshots[item.InventoryID] = snap
			remaining[item.InventoryID] = snap.Quantity
		}
		if item.MedicineID != 0 && snap.MedicineID != item.MedicineID {
			respondError(w, http.StatusBadRequest, "inventory item does not match medicine")
			return
		}
		if remaining[item.InventoryID] < item.Quantity {
			respondError(w, http.StatusBadRequest, "insufficient stock for one or more items")
			return
		}
		remaining[item.InventoryID] -= item.Quantity
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
		pharmacyID, userID, total, req.Discount, req.PaidAmount, due).Scan(&saleID)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "unable to create sale")
		return
	}

	for _, item := range req.Items {
		snap := snapshots[item.InventoryID]
		medicineID := item.MedicineID
		if medicineID == 0 {
			medicineID = snap.MedicineID
		}
		subtotal := float64(item.Quantity) * snap.SalePrice
		if _, err := tx.Exec(`INSERT INTO sale_items (sale_id, medicine_id, inventory_id, quantity, unit_price, subtotal) VALUES ($1, $2, $3, $4, $5, $6)`,
			saleID, medicineID, snap.ID, item.Quantity, snap.SalePrice, subtotal); err != nil {
			respondError(w, http.StatusInternalServerError, "unable to save sale items: "+err.Error())
			return
		}
	}

	for inventoryID, snap := range snapshots {
		newQty := remaining[inventoryID]
		if _, err := tx.Exec(`UPDATE inventory SET quantity = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2`, newQty, snap.ID); err != nil {
			respondError(w, http.StatusInternalServerError, "unable to update inventory")
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
	pharmacyID := pharmacyIDFromContext(r)
	if pharmacyID <= 0 {
		respondError(w, http.StatusForbidden, "invalid pharmacy context")
		return
	}
	query := `SELECT COALESCE(SUM(total_amount - discount),0) AS revenue, COUNT(*) AS count FROM sales WHERE DATE(created_at) = CURRENT_DATE AND pharmacy_id = $1`
	args := []interface{}{pharmacyID}
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
	pharmacyID := pharmacyIDFromContext(r)
	if pharmacyID <= 0 {
		respondError(w, http.StatusForbidden, "invalid pharmacy context")
		return
	}
	query := `SELECT COALESCE(SUM(total_amount - discount),0) AS revenue, COUNT(*) AS count FROM sales WHERE DATE(created_at) >= date_trunc('month', CURRENT_DATE) AND pharmacy_id = $1`
	args := []interface{}{pharmacyID}
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
	SaleID      int64   `db:"sale_id" json:"sale_id"`
	MedicineID  int64   `db:"medicine_id" json:"medicine_id"`
	InventoryID int64   `db:"inventory_id" json:"inventory_id"`
	BrandName   string  `db:"brand_name" json:"brand_name"`
	Quantity    int64   `db:"quantity" json:"quantity"`
	UnitPrice   float64 `db:"unit_price" json:"unit_price"`
	Subtotal    float64 `db:"subtotal" json:"subtotal"`
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

	pharmacyID := pharmacyIDFromContext(r)
	if pharmacyID <= 0 {
		respondError(w, http.StatusForbidden, "invalid pharmacy context")
		return
	}
	args = append(args, pharmacyID)
	clauses = append(clauses, fmt.Sprintf("pharmacy_id = $%d", len(args)))

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

	itemsQuery, itemsArgs, err := sqlx.In(`SELECT si.sale_id, si.medicine_id, si.inventory_id, si.quantity, si.unit_price, si.subtotal, m.brand_name
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
