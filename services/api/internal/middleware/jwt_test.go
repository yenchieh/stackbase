package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

var testSecret = []byte("test-secret")

func signHS256(t *testing.T, claims jwt.MapClaims) string {
	t.Helper()
	s, err := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(testSecret)
	if err != nil {
		t.Fatalf("sign: %v", err)
	}
	return s
}

// a /me-like protected handler: 200 + proves claims reached the context, else 500
func protected() http.Handler {
	return JWTValidate(testSecret)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if _, ok := ClaimsFrom(r.Context()); !ok {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusOK)
	}))
}

func doAuthed(token string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, "/me", nil)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	protected().ServeHTTP(rec, req)
	return rec
}

func TestJWTValidTokenPassesAndSetsClaims(t *testing.T) {
	tok := signHS256(t, jwt.MapClaims{"sub": "u1", "exp": time.Now().Add(time.Hour).Unix()})
	if code := doAuthed(tok).Code; code != http.StatusOK {
		t.Fatalf("code = %d, want 200", code)
	}
}

func TestJWTMissingTokenRejected(t *testing.T) {
	if code := doAuthed("").Code; code != http.StatusUnauthorized {
		t.Fatalf("code = %d, want 401", code)
	}
}

func TestJWTBadSignatureRejected(t *testing.T) {
	bad, _ := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub": "u1", "exp": time.Now().Add(time.Hour).Unix(),
	}).SignedString([]byte("wrong-secret"))
	if code := doAuthed(bad).Code; code != http.StatusUnauthorized {
		t.Fatalf("code = %d, want 401", code)
	}
}

func TestJWTExpiredRejected(t *testing.T) {
	expired := signHS256(t, jwt.MapClaims{"sub": "u1", "exp": time.Now().Add(-time.Hour).Unix()})
	if code := doAuthed(expired).Code; code != http.StatusUnauthorized {
		t.Fatalf("code = %d, want 401", code)
	}
}

// alg-confusion guard: a token with alg=none must be rejected.
func TestJWTNoneAlgRejected(t *testing.T) {
	noneTok, _ := jwt.NewWithClaims(jwt.SigningMethodNone, jwt.MapClaims{"sub": "u1"}).
		SignedString(jwt.UnsafeAllowNoneSignatureType)
	if code := doAuthed(noneTok).Code; code != http.StatusUnauthorized {
		t.Fatalf("alg=none was ACCEPTED (code %d) — alg pinning is broken", code)
	}
}
