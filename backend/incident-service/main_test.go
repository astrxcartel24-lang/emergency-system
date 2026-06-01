package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/gin-gonic/gin"
)

func init() {
	// Set Gin to test mode to avoid verbose debug outputs during tests
	gin.SetMode(gin.TestMode)
}

func TestHealthCheck(t *testing.T) {
	r := gin.New()
	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "OK"})
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/health", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200, got %d", w.Code)
	}

	var resp map[string]string
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("Failed to parse JSON response: %v", err)
	}

	if resp["status"] != "OK" {
		t.Errorf("Expected status 'OK', got %q", resp["status"])
	}
}

func TestInboundSMSWebhook(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("failed to open sqlmock: %s", err)
	}
	defer db.Close()

	svc := NewIncidentService(db)

	r := gin.New()
	r.POST("/api/v1/sms/inbound", InboundSMSHandler(svc))

	// Mock database query for CreateFromSMS -> Create
	rows := sqlmock.NewRows([]string{"id", "type", "description", "lat", "lng", "severity", "status", "role", "location_name", "created_at", "updated_at"}).
		AddRow("generated-sms-uuid", TypeFlood, "families stranded", 0.0, 0.0, SeverityCritical, StatusActive, RoleEyewitness, "WESTLANDS", time.Now(), time.Now())

	mock.ExpectQuery(`^INSERT INTO incidents`).
		WithArgs(
			sqlmock.AnyArg(),
			TypeFlood,
			"families stranded",
			0.0,
			0.0,
			SeverityCritical,
			StatusActive,
			RoleEyewitness,
			"WESTLANDS",
			sqlmock.AnyArg(),
			sqlmock.AnyArg(),
		).
		WillReturnRows(rows)

	// Simulate Africa's Talking form data parameters
	form := url.Values{}
	form.Add("from", "+254712345678")
	form.Add("text", "FLOOD WESTLANDS CRITICAL families stranded")

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/api/v1/sms/inbound", strings.NewReader(form.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	r.ServeHTTP(w, req)

	if w.Code != http.StatusCreated {
		t.Fatalf("Expected status 201 Created, got %d. Body: %s", w.Code, w.Body.String())
	}

	var inc Incident
	if err := json.Unmarshal(w.Body.Bytes(), &inc); err != nil {
		t.Fatalf("Failed to decode response incident: %v", err)
	}

	if inc.ID != "generated-sms-uuid" || inc.Type != TypeFlood || inc.Severity != SeverityCritical || inc.LocationName != "WESTLANDS" {
		t.Errorf("SMS creation mapped incorrectly: %+v", inc)
	}
}

func TestInboundSMSWebhookIgnored(t *testing.T) {
	db, _, _ := sqlmock.New()
	defer db.Close()
	svc := NewIncidentService(db)

	r := gin.New()
	r.POST("/api/v1/sms/inbound", InboundSMSHandler(svc))

	// Invalid SMS format (too few tokens)
	form := url.Values{}
	form.Add("from", "+254712345678")
	form.Add("text", "FLOOD") // Just one word, not enough tokens

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/api/v1/sms/inbound", strings.NewReader(form.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected 200 OK for ignored formats, got %d", w.Code)
	}

	var resp map[string]string
	json.Unmarshal(w.Body.Bytes(), &resp)
	if resp["status"] != "ignored" || resp["reason"] != "too few tokens" {
		t.Errorf("Unexpected response for ignored format: %+v", resp)
	}
}
