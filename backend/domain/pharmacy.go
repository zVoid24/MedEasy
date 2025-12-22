package domain

type Pharmacy struct {
	ID        int64  `db:"id" json:"id"`
	Name      string `db:"name" json:"name"`
	Address   string `db:"address" json:"address"`
	Location  string `db:"location" json:"location"`
	OwnerID   *int64 `db:"owner_id" json:"owner_id,omitempty"`
	CreatedAt string `db:"created_at" json:"created_at"`
}
