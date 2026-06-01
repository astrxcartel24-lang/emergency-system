package main

import (
	"math"
)

const earthRadiusKm = 6371.0

// HaversineKm calculates the great-circle distance between two coordinates in kilometers
func HaversineKm(lat1, lng1, lat2, lng2 float64) float64 {
	dLat := (lat2 - lat1) * math.Pi / 180.0
	dLng := (lng2 - lng1) * math.Pi / 180.0

	lat1Rad := lat1 * math.Pi / 180.0
	lat2Rad := lat2 * math.Pi / 180.0

	a := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(lat1Rad)*math.Cos(lat2Rad)*
		math.Sin(dLng/2)*math.Sin(dLng/2)

	c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
	return earthRadiusKm * c
}

// BoundingBox returns a rectangular bounding box around a center point for a given radius in kilometers
func BoundingBox(lat, lng, radiusKm float64) (minLat, maxLat, minLng, maxLng float64) {
	latDelta := (radiusKm / earthRadiusKm) * (180.0 / math.Pi)
	minLat = lat - latDelta
	maxLat = lat + latDelta

	radLat := lat * math.Pi / 180.0
	cosLat := math.Cos(radLat)

	var lngDelta float64
	if cosLat > 1e-6 {
		lngDelta = (radiusKm / (earthRadiusKm * cosLat)) * (180.0 / math.Pi)
	} else {
		lngDelta = 360.0
	}
	minLng = lng - lngDelta
	maxLng = lng + lngDelta

	// Clip bounds to valid lat/lng ranges
	if minLat < -90.0 {
		minLat = -90.0
	}
	if maxLat > 90.0 {
		maxLat = 90.0
	}
	if minLng < -180.0 {
		minLng = -180.0
	}
	if maxLng > 180.0 {
		maxLng = 180.0
	}

	return minLat, maxLat, minLng, maxLng
}

// FilterByRadius post-filters a slice of Incident to a true circle after a bounding box DB query
func FilterByRadius(incidents []Incident, lat, lng, radiusKm float64) []Incident {
	filtered := make([]Incident, 0)
	for _, inc := range incidents {
		dist := HaversineKm(lat, lng, inc.Lat, inc.Lng)
		if dist <= radiusKm {
			filtered = append(filtered, inc)
		}
	}
	return filtered
}
