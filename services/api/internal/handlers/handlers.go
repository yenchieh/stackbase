// Package handlers holds the HTTP handlers. Healthz is public; Me is meant to
// run behind middleware.JWTValidate and simply echoes the validated claims —
// proof of the protected-route pattern, not a user system.
package handlers

import (
	"net/http"

	"github.com/yenchieh/stackbase/internal/middleware"
	"github.com/yenchieh/stackbase/internal/respond"
)

// Healthz is the public liveness/readiness target.
func Healthz(w http.ResponseWriter, r *http.Request) {
	respond.JSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// Me echoes the validated JWT claims placed in context by JWTValidate.
func Me(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFrom(r.Context())
	if !ok {
		respond.Error(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	respond.JSON(w, http.StatusOK, claims)
}
