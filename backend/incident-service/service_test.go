package main

import (
	"database/sql"
	"errors"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestCreate(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("failed to open sqlmock: %s", err)
	}
	defer db.Close()

	svc := NewIncidentService(db)

	// Test Case 1: Successful Incident Creation
	req := CreateIncidentRequest{
		Type:         TypeFire,
		Description:  "Huge warehouse fire",
		Lat:          -1.286389,
		Lng:          36.817223,
		Severity:     SeverityCritical,
		Role:         RoleEyewitness,
		LocationName: "Industrial Area",
	}

	rows := sqlmock.NewRows([]string{"id", "type", "description", "lat", "lng", "severity", "status", "role", "location_name", "created_at", "updated_at"}).
		AddRow("mock-uuid", req.Type, req.Description, req.Lat, req.Lng, req.Severity, StatusActive, req.Role, req.LocationName, time.Now(), time.Now())

	mock.ExpectQuery(`^INSERT INTO incidents`).
		WithArgs(
			sqlmock.AnyArg(), // ID
			req.Type,
			req.Description,
			req.Lat,
			req.Lng,
			req.Severity,
			StatusActive,
			req.Role,
			req.LocationName,
			sqlmock.AnyArg(), // CreatedAt
			sqlmock.AnyArg(), // UpdatedAt
		).
		WillReturnRows(rows)

	inc, err := svc.Create(req)
	if err != nil {
		t.Fatalf("Expected no error, got %v", err)
	}
	if inc.ID != "mock-uuid" || inc.Type != req.Type || inc.Description != req.Description {
		t.Errorf("Unexpected created incident values: %+v", inc)
	}

	// Test Case 2: Validation Failure - Invalid Type
	reqInvalid := CreateIncidentRequest{
		Type:         IncidentType("tornado"), // invalid enum type
		Description:  "Huge tornado",
		Lat:          -1.286389,
		Lng:          36.817223,
		Severity:     SeverityCritical,
		Role:         RoleEyewitness,
		LocationName: "Industrial Area",
	}

	_, err = svc.Create(reqInvalid)
	if !errors.Is(err, ErrInvalidInput) {
		t.Errorf("Expected ErrInvalidInput, got %v", err)
	}
}

func TestGetByID(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("failed to open sqlmock: %s", err)
	}
	defer db.Close()

	svc := NewIncidentService(db)
	mockID := "test-incident-id"

	// Test Case 1: Found incident
	rows := sqlmock.NewRows([]string{"id", "type", "description", "lat", "lng", "severity", "status", "role", "location_name", "created_at", "updated_at"}).
		AddRow(mockID, TypeFlood, "Flooding in apartments", -1.2, 36.8, SeverityModerate, StatusActive, RoleVictim, "Highrise", time.Now(), time.Now())

	mock.ExpectQuery(`^SELECT (.+) FROM incidents WHERE id = \$1`).
		WithArgs(mockID).
		WillReturnRows(rows)

	inc, err := svc.GetByID(mockID)
	if err != nil {
		t.Fatalf("Expected no error, got %v", err)
	}
	if inc.ID != mockID || inc.Type != TypeFlood {
		t.Errorf("Unexpected incident: %+v", inc)
	}

	// Test Case 2: Incident not found
	mock.ExpectQuery(`^SELECT (.+) FROM incidents WHERE id = \$1`).
		WithArgs("nonexistent").
		WillReturnError(sql.ErrNoRows)

	_, err = svc.GetByID("nonexistent")
	if !errors.Is(err, ErrNotFound) {
		t.Errorf("Expected ErrNotFound, got %v", err)
	}
}

func TestUpdateStatus(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("failed to open sqlmock: %s", err)
	}
	defer db.Close()

	svc := NewIncidentService(db)
	mockID := "test-incident-id"

	// Test Case 1: Successful transition
	req := UpdateStatusRequest{Status: StatusResponding}
	rows := sqlmock.NewRows([]string{"id", "type", "description", "lat", "lng", "severity", "status", "role", "location_name", "created_at", "updated_at"}).
		AddRow(mockID, TypeMedical, "Injury", 1.0, 2.0, SeverityStable, StatusResponding, RoleResponder, "Clinic", time.Now(), time.Now())

	mock.ExpectQuery(`^UPDATE incidents SET status = \$1, updated_at = \$2 WHERE id = \$3`).
		WithArgs(StatusResponding, sqlmock.AnyArg(), mockID).
		WillReturnRows(rows)

	inc, err := svc.UpdateStatus(mockID, req)
	if err != nil {
		t.Fatalf("Expected no error, got %v", err)
	}
	if inc.Status != StatusResponding {
		t.Errorf("Expected status %s, got %s", StatusResponding, inc.Status)
	}

	// Test Case 2: Invalid status transition
	reqInvalid := UpdateStatusRequest{Status: IncidentStatus("archived")}
	_, err = svc.UpdateStatus(mockID, reqInvalid)
	if !errors.Is(err, ErrInvalidStatus) {
		t.Errorf("Expected ErrInvalidStatus, got %v", err)
	}
}

func TestGetRecent(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("failed to open sqlmock: %s", err)
	}
	defer db.Close()

	svc := NewIncidentService(db)

	rows := sqlmock.NewRows([]string{"id", "type", "description", "lat", "lng", "severity", "status", "role", "location_name", "created_at", "updated_at"}).
		AddRow("1", TypeHazmat, "Spill", 1.2, 36.4, SeverityCritical, StatusActive, RoleResponder, "Port", time.Now(), time.Now()).
		AddRow("2", TypeMedical, "Fever", 1.3, 36.5, SeverityModerate, StatusResponding, RoleVictim, "Clinic", time.Now(), time.Now())

	mock.ExpectQuery(`^SELECT (.+) FROM incidents WHERE status IN \('active', 'responding'\) ORDER BY CASE severity`).
		WithArgs(10).
		WillReturnRows(rows)

	list, err := svc.GetRecent(10)
	if err != nil {
		t.Fatalf("Expected no error, got %v", err)
	}
	if len(list) != 2 {
		t.Errorf("Expected 2 incidents, got %d", len(list))
	}
}
