-- Enable UUID extension if needed
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Define custom enum types matching models.go const definitions
CREATE TYPE incident_type AS ENUM (
    'fire',
    'flood',
    'collapse',
    'medical',
    'windstorm',
    'hazmat',
    'power_outage',
    'other'
);

CREATE TYPE severity_level AS ENUM (
    'critical',
    'moderate',
    'stable'
);

CREATE TYPE incident_status AS ENUM (
    'active',
    'responding',
    'resolved'
);

CREATE TYPE reporter_role AS ENUM (
    'eyewitness',
    'victim',
    'responder'
);

-- Incidents table definition
CREATE TABLE incidents (
    id VARCHAR(36) PRIMARY KEY,
    type incident_type NOT NULL,
    description TEXT NOT NULL CHECK (char_length(description) >= 3 AND char_length(description) <= 1000),
    lat DOUBLE PRECISION NOT NULL CHECK (lat >= -90 AND lat <= 90),
    lng DOUBLE PRECISION NOT NULL CHECK (lng >= -180 AND lng <= 180),
    severity severity_level NOT NULL,
    status incident_status NOT NULL DEFAULT 'active',
    role reporter_role NOT NULL,
    location_name VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for performance optimization on geolocation and filters
CREATE INDEX idx_incidents_lat_lng ON incidents (lat, lng);
CREATE INDEX idx_incidents_status ON incidents (status);
CREATE INDEX idx_incidents_type ON incidents (type);
CREATE INDEX idx_incidents_severity ON incidents (severity);
