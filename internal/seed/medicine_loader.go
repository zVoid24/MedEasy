package seed

import (
	"encoding/csv"
	"io"
	"log"
	"os"
	"strings"

	"github.com/jmoiron/sqlx"
)

// LoadMedicines ingests the CSV into the medicines table, ignoring duplicates.
func LoadMedicines(db *sqlx.DB, csvPath string) {
	file, err := os.Open(csvPath)
	if err != nil {
		log.Printf("unable to load medicine catalog %s: %v", csvPath, err)
		return
	}
	defer file.Close()

	reader := csv.NewReader(file)
	// Skip header
	if _, err := reader.Read(); err != nil {
		log.Printf("unable to read medicine header: %v", err)
		return
	}

	tx, err := db.Beginx()
	if err != nil {
		log.Printf("unable to start medicine transaction: %v", err)
		return
	}
	stmt, err := tx.Preparex(`INSERT OR IGNORE INTO medicines (brand_id, brand_name, type, generic_name, manufacturer) VALUES (?, ?, ?, ?, ?)`)
	if err != nil {
		log.Printf("unable to prepare medicine insert: %v", err)
		_ = tx.Rollback()
		return
	}
	defer stmt.Close()

	rows := 0
	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			log.Printf("unable to read medicine row: %v", err)
			continue
		}
		if len(record) < 9 {
			continue
		}
		brandID := strings.TrimSpace(record[0])
		brandName := strings.TrimSpace(record[1])
		medType := strings.TrimSpace(record[2])
		generic := strings.TrimSpace(record[5])
		manufacturer := strings.TrimSpace(record[7])

		if brandName == "" {
			continue
		}

		if _, err := stmt.Exec(brandID, brandName, medType, generic, manufacturer); err != nil {
			log.Printf("unable to insert medicine %s: %v", brandName, err)
		} else {
			rows++
		}
	}

	if err := tx.Commit(); err != nil {
		log.Printf("unable to commit medicine seed: %v", err)
	} else {
		log.Printf("seeded medicine catalog with %d rows", rows)
	}
}
