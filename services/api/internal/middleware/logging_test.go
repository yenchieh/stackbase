package middleware

import (
	"bytes"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestLoggingRecordsRequest(t *testing.T) {
	var buf bytes.Buffer
	logger := slog.New(slog.NewJSONHandler(&buf, nil))

	h := Logging(logger)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusCreated)
	}))
	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/things", nil))

	var line map[string]any
	if err := json.Unmarshal(buf.Bytes(), &line); err != nil {
		t.Fatalf("log line not JSON: %v (%q)", err, buf.String())
	}
	if line["method"] != "GET" || line["path"] != "/things" {
		t.Fatalf("log = %v, want method=GET path=/things", line)
	}
	if line["status"] != float64(http.StatusCreated) {
		t.Fatalf("status = %v, want 201", line["status"])
	}
}
