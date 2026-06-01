package main

import (
	"math"
	"testing"
)

func TestHaversineKm(t *testing.T) {
	// Test Case 1: Same coordinates should have 0 distance
	distSame := HaversineKm(1.286389, 36.817223, 1.286389, 36.817223)
	if distSame != 0.0 {
		t.Errorf("Expected 0 distance, got %f", distSame)
	}

	// Test Case 2: Nairobi (-1.286389, 36.817223) to Kibera (-1.303333, 36.790000)
	// Approximate distance is ~3.6 km
	distNK := HaversineKm(-1.286389, 36.817223, -1.303333, 36.790000)
	expectedApprox := 3.6
	if math.Abs(distNK-expectedApprox) > 0.5 {
		t.Errorf("Nairobi to Kibera distance expected approx %f km, got %f km", expectedApprox, distNK)
	}

	// Test Case 3: Equator degree distance (0, 0) to (0, 1)
	// 1 degree longitude at equator is approx 111.19 km
	distEquator := HaversineKm(0.0, 0.0, 0.0, 1.0)
	if math.Abs(distEquator-111.19) > 0.5 {
		t.Errorf("Equator degree distance expected approx 111.19 km, got %f km", distEquator)
	}
}

func TestBoundingBox(t *testing.T) {
	lat := -1.286389
	lng := 36.817223
	radius := 10.0 // 10 km

	minLat, maxLat, minLng, maxLng := BoundingBox(lat, lng, radius)

	// Latitude bounds verification
	if minLat >= lat || maxLat <= lat {
		t.Errorf("Invalid latitude bounds: lat=%f, minLat=%f, maxLat=%f", lat, minLat, maxLat)
	}

	// Longitude bounds verification
	if minLng >= lng || maxLng <= lng {
		t.Errorf("Invalid longitude bounds: lng=%f, minLng=%f, maxLng=%f", lng, minLng, maxLng)
	}

	// Test clamping for values out of bounds
	minLatClamp, maxLatClamp, _, _ := BoundingBox(89.9, 0.0, 100.0)
	if maxLatClamp > 90.0 {
		t.Errorf("Latitude max clamp failed: got %f, max allowed 90.0", maxLatClamp)
	}
	if minLatClamp >= 89.9 {
		t.Errorf("Expected minLat to decrease, got %f", minLatClamp)
	}
}

func TestFilterByRadius(t *testing.T) {
	latCenter := -1.286389
	lngCenter := 36.817223
	radius := 5.0 // 5 km radius limit

	incidents := []Incident{
		{
			ID:   "1",
			Lat:  -1.286389,
			Lng:  36.817223, // 0 km distance (inside)
			Type: TypeFire,
		},
		{
			ID:   "2",
			Lat:  -1.303333,
			Lng:  36.790000, // ~3.5 km distance (inside)
			Type: TypeFlood,
		},
		{
			ID:   "3",
			Lat:  -1.500000,
			Lng:  37.000000, // ~31 km distance (outside)
			Type: TypeCollapse,
		},
	}

	filtered := FilterByRadius(incidents, latCenter, lngCenter, radius)

	if len(filtered) != 2 {
		t.Fatalf("Expected 2 filtered incidents, got %d", len(filtered))
	}

	if filtered[0].ID != "1" || filtered[1].ID != "2" {
		t.Errorf("Filtered incidents are incorrect: %+v", filtered)
	}
}
