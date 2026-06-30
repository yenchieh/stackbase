// Package respond centralizes JSON responses so handlers and middleware share
// one error shape: {"error": msg} (the project convention — never http.Error).
package respond

import (
	"encoding/json"
	"net/http"
)

// JSON writes v as a JSON body with the given status code.
func JSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

// Error writes {"error": msg} with the given status code.
func Error(w http.ResponseWriter, code int, msg string) {
	JSON(w, code, map[string]string{"error": msg})
}
