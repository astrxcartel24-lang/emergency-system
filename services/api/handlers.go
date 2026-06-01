package main

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"strings"
)

// ─────────────────────────────────────────────
//  Response helpers
// ─────────────────────────────────────────────

func writeJSON(w http.ResponseWriter, status int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		log.Printf("writeJSON error: %v", err)
	}
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

// ─────────────────────────────────────────────
//  Handler wiring
// ─────────────────────────────────────────────

// registerRoutes mounts all endpoints onto mux.
func registerRoutes(mux *http.ServeMux, store *Store, hub *Hub) {
	// Health check — useful for the whole team to verify the server is up
	mux.HandleFunc("/health", handleHealth)

	// WebSocket — GET /api/ws
	mux.HandleFunc("/api/ws", hub.ServeWS)

	// /api/incidents/nearby must be registered before /api/incidents/
	// so the mux matches it correctly
	mux.HandleFunc("/api/incidents/nearby", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			writeError(w, http.StatusMethodNotAllowed, "GET only")
			return
		}
		handleNearby(w, r, store)
	})

	mux.HandleFunc("/api/incidents/", func(w http.ResponseWriter, r *http.Request) {
		// Matches /api/incidents/<id>/status
		path := strings.TrimPrefix(r.URL.Path, "/api/incidents/")
		parts := strings.Split(strings.Trim(path, "/"), "/")

		if len(parts) == 2 && parts[1] == "status" {
			if r.Method != http.MethodPatch {
				writeError(w, http.StatusMethodNotAllowed, "PATCH only")
				return
			}
			handleUpdateStatus(w, r, store, hub, parts[0])
			return
		}

		// Matches /api/incidents/<id>
		if len(parts) == 1 && parts[0] != "" {
			if r.Method != http.MethodGet {
				writeError(w, http.StatusMethodNotAllowed, "GET only")
				return
			}
			handleGetOne(w, r, store, parts[0])
			return
		}

		writeError(w, http.StatusNotFound, "route not found")
	})

	mux.HandleFunc("/api/incidents", func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodPost:
			handleCreate(w, r, store, hub)
		case http.MethodGet:
			handleGetAll(w, r, store)
		default:
			writeError(w, http.StatusMethodNotAllowed, "GET or POST only")
		}
	})
}

// ─────────────────────────────────────────────
//  Handlers
// ─────────────────────────────────────────────

// GET /health
func handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"status":  "ok",
		"service": "emergency-api",
		"version": "1.0.0",
	})
}

// POST /api/incidents
func handleCreate(w http.ResponseWriter, r *http.Request, store *Store, hub *Hub) {
	var req CreateIncidentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid JSON body")
		return
	}

	if errMsg := req.Validate(); errMsg != "" {
		writeError(w, http.StatusBadRequest, errMsg)
		return
	}

	inc := store.Create(&req)

	// Broadcast to all connected dispatcher dashboards (WebSocket)
	hub.Broadcast(EventIncidentCreated, inc)

	// HTTP POST to notification service (Member 6) — non-blocking
	notifyIncidentCreated(inc)

	writeJSON(w, http.StatusCreated, inc)
}

// GET /api/incidents
func handleGetAll(w http.ResponseWriter, r *http.Request, store *Store) {
	all := store.GetAll()
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"incidents": all,
		"count":     len(all),
	})
}

// GET /api/incidents/:id
func handleGetOne(w http.ResponseWriter, r *http.Request, store *Store, id string) {
	inc := store.GetByID(id)
	if inc == nil {
		writeError(w, http.StatusNotFound, "incident not found")
		return
	}
	writeJSON(w, http.StatusOK, inc)
}

// PATCH /api/incidents/:id/status
func handleUpdateStatus(w http.ResponseWriter, r *http.Request, store *Store, hub *Hub, id string) {
	var req UpdateStatusRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	if req.Status == "" {
		writeError(w, http.StatusBadRequest, "status is required")
		return
	}

	inc, ok := store.UpdateStatus(id, req.Status)
	if !ok {
		writeError(w, http.StatusBadRequest, "incident not found or invalid status")
		return
	}

	hub.Broadcast(EventStatusUpdated, inc)

	log.Printf("[NOTIFY] Incident %s status → %s", id, req.Status)

	writeJSON(w, http.StatusOK, inc)
}

// GET /api/incidents/nearby?lat=-1.29&lng=36.82&radius=5
func handleNearby(w http.ResponseWriter, r *http.Request, store *Store) {
	q := r.URL.Query()

	lat, err := strconv.ParseFloat(q.Get("lat"), 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "lat must be a float")
		return
	}
	lng, err := strconv.ParseFloat(q.Get("lng"), 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "lng must be a float")
		return
	}

	radius := 5.0 // default 5 km
	if rv := q.Get("radius"); rv != "" {
		if v, err := strconv.ParseFloat(rv, 64); err == nil && v > 0 {
			radius = v
		}
	}

	nearby := store.GetNearby(lat, lng, radius)
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"incidents": nearby,
		"count":     len(nearby),
		"center":    map[string]float64{"lat": lat, "lng": lng},
		"radius_km": radius,
	})
}
