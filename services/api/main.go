package main

import (
	"log"
	"net/http"
	"os"
	"time"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8090"
	}

	// In-memory store (swap for PostgreSQL in Phase 8)
	store := NewStore()

	// WebSocket hub
	hub := NewHub()

	// Routes
	mux := http.NewServeMux()
	registerRoutes(mux, store, hub)

	// CORS + logging middleware
	handler := corsMiddleware(loggingMiddleware(mux))

	srv := &http.Server{
		Addr:         ":" + port,
		Handler:      handler,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	log.Printf("Backend-API  starting on :%s", port)
	log.Printf("   POST   /api/incidents            — report incident")
	log.Printf("   GET    /api/incidents            — list all incidents")
	log.Printf("   GET    /api/incidents/:id        — get single incident")
	log.Printf("   PATCH  /api/incidents/:id/status — update status")
	log.Printf("   GET    /api/incidents/nearby     — nearby incidents")
	log.Printf("   GET    /api/ws                   — WebSocket (live updates)")
	log.Printf("   GET    /health                   — health check")
	log.Printf("   Seed data loaded — 3 sample incidents ready")

	if err := srv.ListenAndServe(); err != nil {
		log.Fatalf("server error: %v", err)
	}
}

// corsMiddleware allows Flutter, web dashboard, and hotline to call the API
// from any origin during the hackathon.
func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PATCH, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Requested-With")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next.ServeHTTP(w, r)
	})
}

func loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rw := &responseWriter{ResponseWriter: w, status: 200}
		next.ServeHTTP(rw, r)
		log.Printf("%s %s %d %v", r.Method, r.URL.Path, rw.status, time.Since(start))
	})
}

type responseWriter struct {
	http.ResponseWriter
	status int
}

func (rw *responseWriter) WriteHeader(status int) {
	rw.status = status
	rw.ResponseWriter.WriteHeader(status)
}
