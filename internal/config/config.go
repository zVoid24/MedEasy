package config

import (
	"log"
	"os"
	"strconv"
)

// Config holds application configuration values.
type Config struct {
	Secret      string
	DatabaseDSN string
	HTTPPort    string
}

// Load reads configuration from environment variables with reasonable defaults.
func Load() Config {
	secret := os.Getenv("SECRET")
	if secret == "" {
		secret = "dev_secret"
	}

	port := os.Getenv("HTTP_PORT")
	if port == "" {
		port = "8080"
	}

	// Allow overriding database path, default to local SQLite file.
	dsn := os.Getenv("DATABASE_DSN")
	if dsn == "" {
		dsn = "file:medeasy.db?_busy_timeout=5000&_fk=1"
	}

	// Validate that port is numeric.
	if _, err := strconv.Atoi(port); err != nil {
		log.Printf("invalid HTTP_PORT value %q, defaulting to 8080", port)
		port = "8080"
	}

	return Config{Secret: secret, DatabaseDSN: dsn, HTTPPort: port}
}
