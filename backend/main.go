package main

import (
	"log"
	"net/http"

	"github.com/joho/godotenv"

	"medeasy/m/internal/api"
	"medeasy/m/internal/config"
	"medeasy/m/internal/database"
	"medeasy/m/internal/migrations"
	"medeasy/m/internal/seed"
)

func main() {
	_ = godotenv.Load()

	cfg := config.Load()
	db := database.Connect(cfg.DatabaseDSN)
	defer db.Close()

	migrations.Run(db)
	seed.LoadMedicines(db, "assets/medicine.csv")

	handler := api.New(db, cfg.Secret)

	log.Printf("MedEasy POS server starting on :%s", cfg.HTTPPort)
	if err := http.ListenAndServe(":"+cfg.HTTPPort, handler.Router()); err != nil {
		log.Fatalf("server error: %v", err)
	}
}
