package domain

type Medicine struct {
	ID           int64  `db:"id" json:"id"`
	BrandID      int64  `db:"brand_id" json:"brand_id"`
	BrandName    string `db:"brand_name" json:"brand_name"`
	Type         string `db:"type" json:"type"`
	GenericName  string `db:"generic_name" json:"generic_name"`
	Manufacturer string `db:"manufacturer" json:"manufacturer"`
}
