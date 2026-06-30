package main

import (
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/yenchieh/stackbase/internal/handlers"
	"github.com/yenchieh/stackbase/internal/middleware"
)

// newRouter wires the middleware chain and routes. Healthz is public; Me sits
// behind JWTValidate. RequestID is outermost so Logging can read the id.
func newRouter(secret []byte, logger *slog.Logger) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", handlers.Healthz)
	mux.Handle("GET /me", middleware.JWTValidate(secret)(http.HandlerFunc(handlers.Me)))
	return middleware.RequestID(middleware.Logging(logger)(mux))
}

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	secret := os.Getenv("JWT_SECRET")
	if secret == "" {
		logger.Error("JWT_SECRET is required") // never run with an empty signing key
		os.Exit(1)
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	addr := ":" + port

	srv := &http.Server{
		Addr:              addr,
		Handler:           newRouter([]byte(secret), logger),
		ReadHeaderTimeout: 5 * time.Second, // Slowloris guard
	}
	logger.Info("listening", "addr", addr)
	if err := srv.ListenAndServe(); err != nil {
		logger.Error("server stopped", "err", err)
		os.Exit(1)
	}
}
