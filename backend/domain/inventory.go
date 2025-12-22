package domain

import "time"

type InventoryItem struct {
	ID         int64      `db:"id" json:"id"`
	PharmacyID int64      `db:"pharmacy_id" json:"pharmacy_id"`
	MedicineID int64      `db:"medicine_id" json:"medicine_id"`
	Quantity   int64      `db:"quantity" json:"quantity"`
	CostPrice  float64    `db:"cost_price" json:"cost_price"`
	SalePrice  float64    `db:"sale_price" json:"sale_price"`
	ExpiryDate *time.Time `db:"expiry_date" json:"expiry_date,omitempty"`
	CreatedAt  string     `db:"created_at" json:"created_at"`
	UpdatedAt  string     `db:"updated_at" json:"updated_at"`
}
