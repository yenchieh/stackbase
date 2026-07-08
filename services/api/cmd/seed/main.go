// Command seed inserts demo rows into the database. It is idempotent — every row
// is inserted only if a row with the same name doesn't already exist — so it is
// safe to run repeatedly (`make seed` on the host, `make k8s-seed` in-cluster).
//
// Connection comes from DATABASE_URL, e.g.
//   postgres://stackbase:<pw>@localhost:5432/stackbase?sslmode=disable
// If DATABASE_URL is unset it falls back to a localhost dev default.
package main

import (
	"database/sql"
	"log"
	"os"

	_ "github.com/lib/pq"
)

// demoItems is the deterministic seed set. Add rows here; re-running seed only
// inserts the ones not already present (matched by name).
var demoItems = []string{
	"Welcome to stackbase",
	"Edit services/api and save — the api hot-reloads",
	"Edit services/frontend/src and save — Vite HMR",
}

func main() {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		dsn = "postgres://stackbase:stackbase@localhost:5432/stackbase?sslmode=disable"
		log.Printf("DATABASE_URL unset, using dev default (%s)", dsn)
	}

	db, err := sql.Open("postgres", dsn)
	if err != nil {
		log.Fatalf("open db: %v", err)
	}
	defer db.Close()

	if err := db.Ping(); err != nil {
		log.Fatalf("connect db: %v (is Postgres reachable? did migrations run?)", err)
	}

	inserted := 0
	for _, name := range demoItems {
		// WHERE NOT EXISTS keeps it idempotent — name isn't UNIQUE, so ON CONFLICT
		// can't be used; this inserts each demo row at most once.
		res, err := db.Exec(
			`INSERT INTO demo_items (name)
			 SELECT $1 WHERE NOT EXISTS (SELECT 1 FROM demo_items WHERE name = $1)`,
			name,
		)
		if err != nil {
			log.Fatalf("seed %q: %v", name, err)
		}
		if n, _ := res.RowsAffected(); n > 0 {
			inserted++
		}
	}

	log.Printf("seed complete: %d inserted, %d already present", inserted, len(demoItems)-inserted)
}
