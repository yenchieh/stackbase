package middleware

import (
	"context"

	"github.com/golang-jwt/jwt/v5"
)

type ctxKey int

const (
	requestIDKey ctxKey = iota
	claimsKey
)

// RequestIDFrom returns the request id stored by RequestID, or "" if absent.
func RequestIDFrom(ctx context.Context) string {
	id, _ := ctx.Value(requestIDKey).(string)
	return id
}

// ClaimsFrom returns the validated JWT claims stored by JWTValidate.
func ClaimsFrom(ctx context.Context) (jwt.MapClaims, bool) {
	c, ok := ctx.Value(claimsKey).(jwt.MapClaims)
	return c, ok
}
