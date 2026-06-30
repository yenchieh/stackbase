package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestRequestIDGeneratesWhenAbsent(t *testing.T) {
	var seen string
	h := RequestID(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		seen = RequestIDFrom(r.Context())
	}))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/", nil))

	if seen == "" {
		t.Fatal("handler saw empty request id in context")
	}
	if got := rec.Header().Get("X-Request-Id"); got != seen {
		t.Fatalf("response header %q != context id %q", got, seen)
	}
}

func TestRequestIDReusesIncoming(t *testing.T) {
	var seen string
	h := RequestID(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		seen = RequestIDFrom(r.Context())
	}))
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set("X-Request-Id", "abc123")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)

	if seen != "abc123" {
		t.Fatalf("context id = %q, want abc123", seen)
	}
	if got := rec.Header().Get("X-Request-Id"); got != "abc123" {
		t.Fatalf("response header = %q, want abc123", got)
	}
}
