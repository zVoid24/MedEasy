package config

import (
	"fmt"
	"log"
	"os"
	"strconv"

	"github.com/joho/godotenv"
)

// Config holds application configuration values.
type Config struct {
	Secret      string
	DatabaseDSN string
	HTTPPort    string
}

// Load reads configuration from environment variables with reasonable defaults.
func Load() Config {
	err := godotenv.Overload()
	if err != nil {
		fmt.Println("Failed to load .env file")
		os.Exit(1)
	}
	secret := os.Getenv("SECRET")
	if secret == "" {
		secret = "dev_secret"
	}

	port := os.Getenv("HTTP_PORT")
	if port == "" {
		port = "8080"
	}

	dsn := os.Getenv("DATABASE_DSN")
	if dsn == "" {
		host := os.Getenv("HOST")
		if host == "" {
			host = "localhost"
		}
		user := os.Getenv("USER")
		if user == "" {
			user = "postgres"
		}
		dbPort := os.Getenv("PORT")
		if dbPort == "" {
			dbPort = "5432"
		}
		name := os.Getenv("NAME")
		if name == "" {
			name = "medeasy"
		}
		password := os.Getenv("PASSWORD")
		if password == "" {
			password = "8135"
		}
		dsn = "postgresql://neondb_owner:npg_q17hrZHtWKGi@ep-orange-paper-a1lx87y3-pooler.ap-southeast-1.aws.neon.tech/neondb?sslmode=require&channel_binding=require"
	}

	// Validate that port is numeric.
	if _, err := strconv.Atoi(port); err != nil {
		log.Printf("invalid HTTP_PORT value %q, defaulting to 8080", port)
		port = "8080"
	}

	return Config{Secret: secret, DatabaseDSN: dsn, HTTPPort: port}
}
