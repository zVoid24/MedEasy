package migrations

import (
	"log"

	"github.com/jmoiron/sqlx"
)

// Run creates the database schema required for the POS backend.
func Run(db *sqlx.DB) {
	schema := []string{
		`CREATE TABLE IF NOT EXISTS users (
            id SERIAL PRIMARY KEY,
            username TEXT NOT NULL,
            email TEXT NOT NULL UNIQUE,
            password TEXT NOT NULL,
            role TEXT NOT NULL,
            created_at TIMESTAMPTZ DEFAULT NOW()
        );`,
		`CREATE TABLE IF NOT EXISTS pharmacies (
            id SERIAL PRIMARY KEY,
            name TEXT NOT NULL,
            address TEXT,
            location TEXT,
            owner_id INTEGER REFERENCES users(id),
            created_at TIMESTAMPTZ DEFAULT NOW()
        );`,
		`CREATE TABLE IF NOT EXISTS medicines (
            id SERIAL PRIMARY KEY,
            brand_id INTEGER,
            brand_name TEXT NOT NULL,
            type TEXT,
            generic_name TEXT,
            manufacturer TEXT,
            UNIQUE(brand_id)
        );`,
		`CREATE TABLE IF NOT EXISTS inventory (
            id SERIAL PRIMARY KEY,
            pharmacy_id INTEGER NOT NULL REFERENCES pharmacies(id),
            medicine_id INTEGER NOT NULL REFERENCES medicines(id),
            quantity INTEGER NOT NULL,
            cost_price DOUBLE PRECISION NOT NULL,
            sale_price DOUBLE PRECISION NOT NULL,
            expiry_date DATE,
            created_at TIMESTAMPTZ DEFAULT NOW(),
            updated_at TIMESTAMPTZ DEFAULT NOW()
        );`,
		`CREATE TABLE IF NOT EXISTS sales (
            id SERIAL PRIMARY KEY,
            pharmacy_id INTEGER NOT NULL REFERENCES pharmacies(id),
            user_id INTEGER REFERENCES users(id),
            total_amount DOUBLE PRECISION NOT NULL,
            discount DOUBLE PRECISION DEFAULT 0,
            paid_amount DOUBLE PRECISION DEFAULT 0,
            due_amount DOUBLE PRECISION DEFAULT 0,
            created_at TIMESTAMPTZ DEFAULT NOW()
        );`,
		`CREATE TABLE IF NOT EXISTS sale_items (
            id SERIAL PRIMARY KEY,
            sale_id INTEGER NOT NULL REFERENCES sales(id),
            medicine_id INTEGER NOT NULL REFERENCES medicines(id),
            quantity INTEGER NOT NULL,
            unit_price DOUBLE PRECISION NOT NULL,
            subtotal DOUBLE PRECISION NOT NULL
        );`,
	}

	for _, stmt := range schema {
		if _, err := db.Exec(stmt); err != nil {
			log.Fatalf("migration failed: %v", err)
		}
	}
}
