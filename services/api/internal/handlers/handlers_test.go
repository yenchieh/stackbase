package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"

	"github.com/yenchieh/stackbase/internal/middleware"
)

func TestHealthzOK(t *testing.T) {
	rec := httptest.NewRecorder()
	Healthz(rec, httptest.NewRequest(http.MethodGet, "/healthz", nil))

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	var body map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("body not JSON: %v (%q)", err, rec.Body.String())
	}
	if body["status"] != "ok" {
		t.Fatalf("body = %v, want status=ok", body)
	}
}

// /me is always reached behind JWTValidate, so test it through that middleware.
func TestMeEchoesClaims(t *testing.T) {
	secret := []byte("test-secret")
	tok, _ := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub": "u1", "exp": time.Now().Add(time.Hour).Unix(),
	}).SignedString(secret)

	h := middleware.JWTValidate(secret)(http.HandlerFunc(Me))
	req := httptest.NewRequest(http.MethodGet, "/me", nil)
	req.Header.Set("Authorization", "Bearer "+tok)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("body not JSON: %v", err)
	}
	if body["sub"] != "u1" {
		t.Fatalf("body = %v, want sub=u1", body)
	}
}

func TestMeWithoutClaimsUnauthorized(t *testing.T) {
	rec := httptest.NewRecorder()
	Me(rec, httptest.NewRequest(http.MethodGet, "/me", nil)) // no claims in context

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
}
