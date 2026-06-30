package middleware

import (
	"context"
	"net/http"
	"strings"

	"github.com/golang-jwt/jwt/v5"

	"github.com/yenchieh/stackbase/internal/respond"
)

// JWTValidate validates a Bearer token's HS256 signature and expiry against
// secret, then puts the claims in the context (read with ClaimsFrom). It only
// VALIDATES — it never issues tokens or manages users. WithValidMethods pins
// HS256 so a forged "alg":"none" (or an asymmetric-key confusion) is rejected.
func JWTValidate(secret []byte) func(http.Handler) http.Handler {
	keyFunc := func(*jwt.Token) (any, error) { return secret, nil }
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			raw, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
			if !ok || raw == "" {
				respond.Error(w, http.StatusUnauthorized, "missing bearer token")
				return
			}
			claims := jwt.MapClaims{}
			if _, err := jwt.ParseWithClaims(raw, claims, keyFunc,
				jwt.WithValidMethods([]string{"HS256"})); err != nil {
				respond.Error(w, http.StatusUnauthorized, "invalid token")
				return
			}
			ctx := context.WithValue(r.Context(), claimsKey, claims)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}
