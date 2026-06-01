package main

import "time"

// Enum types
type IncidentType string
type SeverityLevel string
type IncidentStatus string
type ReporterRole string

const (
    TypeFire        IncidentType = "fire"
    TypeFlood       IncidentType = "flood"
    TypeCollapse    IncidentType = "collapse"
    TypeMedical     IncidentType = "medical"
    TypeWindstorm   IncidentType = "windstorm"
    TypeHazmat      IncidentType = "hazmat"
    TypePowerOutage IncidentType = "power_outage"
    TypeOther       IncidentType = "other"
)

const (
    SeverityCritical SeverityLevel = "critical"
    SeverityModerate SeverityLevel = "moderate"
    SeverityStable   SeverityLevel = "stable"
)

const (
    StatusActive     IncidentStatus = "active"
    StatusResponding IncidentStatus = "responding"
    StatusResolved   IncidentStatus = "resolved"
)

const (
    RoleEyewitness ReporterRole = "eyewitness"
    RoleVictim     ReporterRole = "victim"
    RoleResponder  ReporterRole = "responder"
)

type Incident struct {
    ID           string         `json:"id"            db:"id"`
    Type         IncidentType   `json:"type"          db:"type"`
    Description  string         `json:"description"   db:"description"`
    Lat          float64        `json:"lat"           db:"lat"`
    Lng          float64        `json:"lng"           db:"lng"`
    Severity     SeverityLevel  `json:"severity"      db:"severity"`
    Status       IncidentStatus `json:"status"        db:"status"`
    Role         ReporterRole   `json:"role"          db:"role"`
    LocationName string         `json:"location_name" db:"location_name"`
    CreatedAt    time.Time      `json:"created_at"    db:"created_at"`
    UpdatedAt    time.Time      `json:"updated_at"    db:"updated_at"`
}

type CreateIncidentRequest struct {
    Type         IncidentType   `json:"type"          binding:"required"`
    Description  string         `json:"description"   binding:"required,min=3,max=1000"`
    Lat          float64        `json:"lat"           binding:"required,min=-90,max=90"`
    Lng          float64        `json:"lng"           binding:"required,min=-180,max=180"`
    Severity     SeverityLevel  `json:"severity"      binding:"required"`
    Role         ReporterRole   `json:"role"          binding:"required"`
    LocationName string         `json:"location_name"`
}

type UpdateStatusRequest struct {
    Status IncidentStatus `json:"status" binding:"required"`
}

type NearbyQuery struct {
    Lat      float64        `form:"lat"      binding:"required,min=-90,max=90"`
    Lng      float64        `form:"lng"      binding:"required,min=-180,max=180"`
    RadiusKm float64        `form:"radius"   binding:"required,min=0.1,max=100"`
    Type     IncidentType   `form:"type"`
    Severity SeverityLevel  `form:"severity"`
    Status   IncidentStatus `form:"status"`
    Limit    int            `form:"limit"`
}

type SMSReport struct {
    From         string        `json:"from"`
    Type         IncidentType  `json:"type"`
    LocationName string        `json:"location_name"`
    Severity     SeverityLevel `json:"severity"`
    Description  string        `json:"description"`
}
