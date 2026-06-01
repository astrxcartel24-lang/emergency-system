package main

import (
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
)

var (
	ErrNotFound      = errors.New("incident not found")
	ErrInvalidStatus = errors.New("invalid incident status")
	ErrInvalidInput  = errors.New("invalid input data")
)

// Enum validators
func isValidIncidentType(t IncidentType) bool {
	switch t {
	case TypeFire, TypeFlood, TypeCollapse, TypeMedical, TypeWindstorm, TypeHazmat, TypePowerOutage, TypeOther:
		return true
	}
	return false
}

func isValidSeverityLevel(s SeverityLevel) bool {
	switch s {
	case SeverityCritical, SeverityModerate, SeverityStable:
		return true
	}
	return false
}

func isValidReporterRole(r ReporterRole) bool {
	switch r {
	case RoleEyewitness, RoleVictim, RoleResponder:
		return true
	}
	return false
}

func isValidIncidentStatus(s IncidentStatus) bool {
	switch s {
	case StatusActive, StatusResponding, StatusResolved:
		return true
	}
	return false
}

type IncidentService struct {
	db *sql.DB
}

// NewIncidentService creates a new IncidentService
func NewIncidentService(db *sql.DB) *IncidentService {
	return &IncidentService{db: db}
}

// Create inserts and returns the created row
func (s *IncidentService) Create(req CreateIncidentRequest) (*Incident, error) {
	if !isValidIncidentType(req.Type) || !isValidSeverityLevel(req.Severity) || !isValidReporterRole(req.Role) {
		return nil, ErrInvalidInput
	}
	if len(req.Description) < 3 || len(req.Description) > 1000 {
		return nil, ErrInvalidInput
	}
	if req.Lat < -90.0 || req.Lat > 90.0 || req.Lng < -180.0 || req.Lng > 180.0 {
		return nil, ErrInvalidInput
	}

	locName := req.LocationName
	if locName == "" {
		locName = "Unknown Location"
	}

	id := uuid.New().String()
	now := time.Now().UTC()

	var inc Incident
	query := `INSERT INTO incidents (id, type, description, lat, lng, severity, status, role, location_name, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
		RETURNING id, type, description, lat, lng, severity, status, role, location_name, created_at, updated_at`

	err := s.db.QueryRow(query, id, req.Type, req.Description, req.Lat, req.Lng, req.Severity, StatusActive, req.Role, locName, now, now).
		Scan(&inc.ID, &inc.Type, &inc.Description, &inc.Lat, &inc.Lng, &inc.Severity, &inc.Status, &inc.Role, &inc.LocationName, &inc.CreatedAt, &inc.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return &inc, nil
}

// GetByID returns the incident by ID, or ErrNotFound if it doesn't exist
func (s *IncidentService) GetByID(id string) (*Incident, error) {
	var inc Incident
	query := `SELECT id, type, description, lat, lng, severity, status, role, location_name, created_at, updated_at
		FROM incidents
		WHERE id = $1`
	err := s.db.QueryRow(query, id).
		Scan(&inc.ID, &inc.Type, &inc.Description, &inc.Lat, &inc.Lng, &inc.Severity, &inc.Status, &inc.Role, &inc.LocationName, &inc.CreatedAt, &inc.UpdatedAt)
	if err == sql.ErrNoRows {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	return &inc, nil
}

// GetNearby does a bounding box SQL query, then a Go-level Haversine filter to trim to true circle
func (s *IncidentService) GetNearby(q NearbyQuery) ([]Incident, error) {
	if q.Lat < -90.0 || q.Lat > 90.0 || q.Lng < -180.0 || q.Lng > 180.0 {
		return nil, ErrInvalidInput
	}
	if q.RadiusKm <= 0.1 || q.RadiusKm > 100.0 {
		return nil, ErrInvalidInput
	}

	minLat, maxLat, minLng, maxLng := BoundingBox(q.Lat, q.Lng, q.RadiusKm)

	query := `SELECT id, type, description, lat, lng, severity, status, role, location_name, created_at, updated_at
		FROM incidents
		WHERE lat >= $1 AND lat <= $2 AND lng >= $3 AND lng <= $4`

	args := []interface{}{minLat, maxLat, minLng, maxLng}
	placeholderIdx := 5

	if q.Type != "" {
		if !isValidIncidentType(q.Type) {
			return nil, ErrInvalidInput
		}
		query += fmt.Sprintf(" AND type = $%d", placeholderIdx)
		args = append(args, q.Type)
		placeholderIdx++
	}

	if q.Severity != "" {
		if !isValidSeverityLevel(q.Severity) {
			return nil, ErrInvalidInput
		}
		query += fmt.Sprintf(" AND severity = $%d", placeholderIdx)
		args = append(args, q.Severity)
		placeholderIdx++
	}

	if q.Status != "" {
		if !isValidIncidentStatus(q.Status) {
			return nil, ErrInvalidInput
		}
		query += fmt.Sprintf(" AND status = $%d", placeholderIdx)
		args = append(args, q.Status)
		placeholderIdx++
	} else {
		query += " AND status != 'resolved'"
	}

	rows, err := s.db.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var incidents []Incident
	for rows.Next() {
		var inc Incident
		err := rows.Scan(&inc.ID, &inc.Type, &inc.Description, &inc.Lat, &inc.Lng, &inc.Severity, &inc.Status, &inc.Role, &inc.LocationName, &inc.CreatedAt, &inc.UpdatedAt)
		if err != nil {
			return nil, err
		}
		incidents = append(incidents, inc)
	}

	// Filter to true circle
	filtered := FilterByRadius(incidents, q.Lat, q.Lng, q.RadiusKm)

	// Apply Limit in Go
	if q.Limit > 0 && len(filtered) > q.Limit {
		filtered = filtered[:q.Limit]
	}

	return filtered, nil
}

// GetRecent returns active/responding incidents sorted by severity (critical first) then recency
func (s *IncidentService) GetRecent(limit int) ([]Incident, error) {
	if limit <= 0 {
		limit = 20
	}
	if limit > 100 {
		limit = 100
	}

	query := `SELECT id, type, description, lat, lng, severity, status, role, location_name, created_at, updated_at
		FROM incidents
		WHERE status IN ('active', 'responding')
		ORDER BY CASE severity
			WHEN 'critical' THEN 1
			WHEN 'moderate' THEN 2
			WHEN 'stable' THEN 3
			ELSE 4
		END ASC, created_at DESC
		LIMIT $1`

	rows, err := s.db.Query(query, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var incidents []Incident
	for rows.Next() {
		var inc Incident
		err := rows.Scan(&inc.ID, &inc.Type, &inc.Description, &inc.Lat, &inc.Lng, &inc.Severity, &inc.Status, &inc.Role, &inc.LocationName, &inc.CreatedAt, &inc.UpdatedAt)
		if err != nil {
			return nil, err
		}
		incidents = append(incidents, inc)
	}
	return incidents, nil
}

// UpdateStatus updates the status, returns ErrNotFound or ErrInvalidStatus on failure
func (s *IncidentService) UpdateStatus(id string, req UpdateStatusRequest) (*Incident, error) {
	if !isValidIncidentStatus(req.Status) {
		return nil, ErrInvalidStatus
	}

	now := time.Now().UTC()
	var inc Incident
	query := `UPDATE incidents
		SET status = $1, updated_at = $2
		WHERE id = $3
		RETURNING id, type, description, lat, lng, severity, status, role, location_name, created_at, updated_at`

	err := s.db.QueryRow(query, req.Status, now, id).
		Scan(&inc.ID, &inc.Type, &inc.Description, &inc.Lat, &inc.Lng, &inc.Severity, &inc.Status, &inc.Role, &inc.LocationName, &inc.CreatedAt, &inc.UpdatedAt)
	if err == sql.ErrNoRows {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	return &inc, nil
}

// CreateFromSMS creates an incident from a parsed SMS report with lat/lng defaulting to 0,0
func (s *IncidentService) CreateFromSMS(report SMSReport) (*Incident, error) {
	if !isValidIncidentType(report.Type) || !isValidSeverityLevel(report.Severity) {
		return nil, ErrInvalidInput
	}

	desc := report.Description
	if len(desc) < 3 {
		desc = "SMS: " + desc
		if len(desc) < 3 {
			desc = "SMS report from " + report.From
		}
	}
	if len(desc) > 1000 {
		desc = desc[:1000]
	}

	locName := report.LocationName
	if locName == "" {
		locName = "Unknown Location"
	}

	req := CreateIncidentRequest{
		Type:         report.Type,
		Description:  desc,
		Lat:          0.0,
		Lng:          0.0,
		Severity:     report.Severity,
		Role:         RoleEyewitness,
		LocationName: locName,
	}

	return s.Create(req)
}

// NewDB opens the database connection, sets pool limits, and verifies connection via ping
func NewDB(dsn string) (*sql.DB, error) {
	db, err := sql.Open("postgres", dsn)
	if err != nil {
		return nil, err
	}

	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(10)
	db.SetConnMaxLifetime(5 * time.Minute)

	if err := db.Ping(); err != nil {
		db.Close()
		return nil, err
	}

	return db, nil
}
