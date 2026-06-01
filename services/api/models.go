package main

import (
	"sync"
	"time"

	"github.com/google/uuid"
)

type UpdateStatusRequest struct {
	Status IncidentStatus `json:"status" binding:"required"`
}

type Severity string

const (
	SeverityLow      Severity = "low"
	SeverityMedium   Severity = "medium"
	SeverityHigh     Severity = "high"
	SeverityCritical Severity = "critical"
)

type IncidentType string

const (
	TypeFire     IncidentType = "fire"
	TypeMedical  IncidentType = "medical"
	TypeAccident IncidentType = "accident"
	TypeCrime    IncidentType = "crime"
	TypeProtest  IncidentType = "protest"
)

type IncidentStatus string

const (
	StatusPending    IncidentStatus = "pending"
	StatusInProgress IncidentStatus = "in_progress"
	StatusResolved   IncidentStatus = "resolved"
)

type CreateIncidentRequest struct {
	Type        IncidentType `json:"type"`
	Description string       `json:"description"`
	Latitude    float64      `json:"latitude"`
	Longitude   float64      `json:"longitude"`
	Severity    Severity     `json:"severity"`
	ReportedBy  string       `json:"reported_by,omitempty"`
}

type Incident struct {
	ID          string         `json:"id"`
	Type        IncidentType   `json:"type"`
	Description string         `json:"description"`
	Latitude    float64        `json:"latitude"`
	Longitude   float64        `json:"longitude"`
	Severity    Severity       `json:"severity"`
	Status      IncidentStatus `json:"status"`
	ReportedBy  string         `json:"reported_by,omitempty"` // "app", "hotline", "web"
	CreatedAt   time.Time      `json:"created_at"`
	UpdatedAt   time.Time      `json:"updated_at"`
}

func (r *CreateIncidentRequest) Validate() string {
	if r.Type == "" {
		return "type is required"
	}
	validTypes := map[IncidentType]bool{
		TypeFire: true, TypeMedical: true, TypeAccident: true,
		TypeCrime: true, TypeProtest: true,
	}
	if !validTypes[r.Type] {
		return "type must be: fire, medical, accident, crime, protest"
	}
	if r.Description == "" {
		return "description is required"
	}
	if r.Latitude == 0 && r.Longitude == 0 {
		return "latitude and longitude are required"
	}
	validSeverities := map[Severity]bool{
		SeverityLow: true, SeverityMedium: true,
		SeverityHigh: true, SeverityCritical: true,
	}
	if r.Severity == "" {
		r.Severity = SeverityMedium // default
	}
	if !validSeverities[r.Severity] {
		return "severity must be: low, medium, high, critical"
	}
	return ""
}

// ─────────────────────────────────────────────
//  In-memory store (replace with PostgreSQL later)
// ─────────────────────────────────────────────

// Store is a thread-safe in-memory incident store.
type Store struct {
	mu        sync.RWMutex
	incidents map[string]*Incident
	order     []string // preserve insertion order
}

// NewStore creates an empty store with a few seed incidents for demo purposes.
func NewStore() *Store {
	s := &Store{
		incidents: make(map[string]*Incident),
	}
	// Seed data so the Flutter/Web team
	s.seed()
	return s
}

func (s *Store) seed() {
	seeds := []CreateIncidentRequest{
		{
			Type:        TypeFire,
			Description: "House fire reported near Westlands",
			Latitude:    -1.2636,
			Longitude:   36.8030,
			Severity:    SeverityHigh,
			ReportedBy:  "seed",
		},
		{
			Type:        TypeMedical,
			Description: "Road accident on Thika Superhighway, injuries reported",
			Latitude:    -1.2195,
			Longitude:   36.8900,
			Severity:    SeverityCritical,
			ReportedBy:  "hotline",
		},
		{
			Type:        TypeCrime,
			Description: "Robbery reported at CBD",
			Latitude:    -1.2864,
			Longitude:   36.8172,
			Severity:    SeverityMedium,
			ReportedBy:  "app",
		},
	}
	for _, req := range seeds {
		s.Create(&req)
	}
}

// Create stores a new incident and returns it.
func (s *Store) Create(req *CreateIncidentRequest) *Incident {
	now := time.Now().UTC()
	inc := &Incident{
		ID:          uuid.New().String(),
		Type:        req.Type,
		Description: req.Description,
		Latitude:    req.Latitude,
		Longitude:   req.Longitude,
		Severity:    req.Severity,
		Status:      StatusPending,
		ReportedBy:  req.ReportedBy,
		CreatedAt:   now,
		UpdatedAt:   now,
	}
	if inc.ReportedBy == "" {
		inc.ReportedBy = "app"
	}

	s.mu.Lock()
	s.incidents[inc.ID] = inc
	s.order = append(s.order, inc.ID)
	s.mu.Unlock()

	return inc
}

// GetAll returns all incidents, newest first.
func (s *Store) GetAll() []*Incident {
	s.mu.RLock()
	defer s.mu.RUnlock()

	result := make([]*Incident, 0, len(s.order))
	for i := len(s.order) - 1; i >= 0; i-- {
		result = append(result, s.incidents[s.order[i]])
	}
	return result
}

// GetByID returns a single incident or nil.
func (s *Store) GetByID(id string) *Incident {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.incidents[id]
}

// UpdateStatus changes an incident's status.
func (s *Store) UpdateStatus(id string, status IncidentStatus) (*Incident, bool) {
	validStatuses := map[IncidentStatus]bool{
		StatusPending: true, StatusInProgress: true, StatusResolved: true,
	}
	if !validStatuses[status] {
		return nil, false
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	inc, ok := s.incidents[id]
	if !ok {
		return nil, false
	}
	inc.Status = status
	inc.UpdatedAt = time.Now().UTC()
	return inc, true
}

// GetNearby returns incidents within radius km of (lat, lng).
func (s *Store) GetNearby(lat, lng, radiusKm float64) []*Incident {
	s.mu.RLock()
	defer s.mu.RUnlock()

	var result []*Incident
	for _, inc := range s.incidents {
		if HaversineKm(lat, lng, inc.Latitude, inc.Longitude) <= radiusKm {
			result = append(result, inc)
		}
	}
	return result
}
