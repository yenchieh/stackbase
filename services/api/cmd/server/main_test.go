package main

import (
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

var secret = []byte("test-secret")

func testRouter() http.Handler {
	return newRouter(secret, slog.New(slog.NewTextHandler(io.Discard, nil)))
}

func get(t *testing.T, path, token string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, path, nil)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	testRouter().ServeHTTP(rec, req)
	return rec
}

func TestRouterHealthzIsPublic(t *testing.T) {
	rec := get(t, "/healthz", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("healthz status = %d, want 200", rec.Code)
	}
	if rec.Header().Get("X-Request-Id") == "" {
		t.Fatal("missing X-Request-Id (RequestID middleware not wired)")
	}
}

func TestRouterMeRequiresAuth(t *testing.T) {
	if rec := get(t, "/me", ""); rec.Code != http.StatusUnauthorized {
		t.Fatalf("/me without token = %d, want 401", rec.Code)
	}
}

func TestRouterMeWithValidToken(t *testing.T) {
	tok, _ := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub": "u1", "exp": time.Now().Add(time.Hour).Unix(),
	}).SignedString(secret)
	if rec := get(t, "/me", tok); rec.Code != http.StatusOK {
		t.Fatalf("/me with valid token = %d, want 200", rec.Code)
	}
}
