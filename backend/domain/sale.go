package domain

type Sale struct {
	ID          int64   `db:"id" json:"id"`
	PharmacyID  int64   `db:"pharmacy_id" json:"pharmacy_id"`
	UserID      *int64  `db:"user_id" json:"user_id,omitempty"`
	TotalAmount float64 `db:"total_amount" json:"total_amount"`
	Discount    float64 `db:"discount" json:"discount"`
	PaidAmount  float64 `db:"paid_amount" json:"paid_amount"`
	DueAmount   float64 `db:"due_amount" json:"due_amount"`
	CreatedAt   string  `db:"created_at" json:"created_at"`
}

type SaleItem struct {
	ID          int64   `db:"id" json:"id"`
	SaleID      int64   `db:"sale_id" json:"sale_id"`
	MedicineID  int64   `db:"medicine_id" json:"medicine_id"`
	InventoryID int64   `db:"inventory_id" json:"inventory_id"`
	Quantity    int64   `db:"quantity" json:"quantity"`
	UnitPrice   float64 `db:"unit_price" json:"unit_price"`
	Subtotal    float64 `db:"subtotal" json:"subtotal"`
}
