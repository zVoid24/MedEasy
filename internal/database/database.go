package database

import (
	"log"

	"github.com/jmoiron/sqlx"
	_ "modernc.org/sqlite"
)

// Connect opens a SQLite database using the provided DSN.
func Connect(dsn string) *sqlx.DB {
	db, err := sqlx.Connect("sqlite", dsn)
	if err != nil {
		log.Fatalf("failed to connect to database: %v", err)
	}
	db.SetMaxOpenConns(1)
	return db
}
