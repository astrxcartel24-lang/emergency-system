package main

import (
	"errors"
	"fmt"
	"log"
	"os"
	"strings"

	"github.com/gin-gonic/gin"
	_ "github.com/lib/pq"
)

// CORSMiddleware enables CORS for hackathon development
func CORSMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT, PATCH, DELETE")

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}

		c.Next()
	}
}

// CreateIncidentHandler handles POST /api/v1/incidents
func CreateIncidentHandler(svc *IncidentService) gin.HandlerFunc {
	return func(c *gin.Context) {
		var req CreateIncidentRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(400, gin.H{"error": err.Error()})
			return
		}

		inc, err := svc.Create(req)
		if err != nil {
			if errors.Is(err, ErrInvalidInput) {
				c.JSON(400, gin.H{"error": err.Error()})
				return
			}
			c.JSON(500, gin.H{"error": "Internal server error"})
			return
		}

		c.JSON(201, inc)
	}
}

// GetNearbyIncidentsHandler handles GET /api/v1/incidents/nearby
func GetNearbyIncidentsHandler(svc *IncidentService) gin.HandlerFunc {
	return func(c *gin.Context) {
		var q NearbyQuery
		if err := c.ShouldBindQuery(&q); err != nil {
			c.JSON(400, gin.H{"error": err.Error()})
			return
		}

		incidents, err := svc.GetNearby(q)
		if err != nil {
			if errors.Is(err, ErrInvalidInput) {
				c.JSON(400, gin.H{"error": err.Error()})
				return
			}
			c.JSON(500, gin.H{"error": "Internal server error"})
			return
		}

		c.JSON(200, incidents)
	}
}

// GetRecentIncidentsHandler handles GET /api/v1/incidents/recent
func GetRecentIncidentsHandler(svc *IncidentService) gin.HandlerFunc {
	return func(c *gin.Context) {
		limit := 20
		if limitStr := c.Query("limit"); limitStr != "" {
			var parsedLimit int
			if _, err := fmt.Sscanf(limitStr, "%d", &parsedLimit); err == nil && parsedLimit > 0 {
				limit = parsedLimit
			}
		}

		incidents, err := svc.GetRecent(limit)
		if err != nil {
			c.JSON(500, gin.H{"error": "Internal server error"})
			return
		}

		c.JSON(200, incidents)
	}
}

// GetIncidentByIDHandler handles GET /api/v1/incidents/:id
func GetIncidentByIDHandler(svc *IncidentService) gin.HandlerFunc {
	return func(c *gin.Context) {
		id := c.Param("id")
		if id == "" {
			c.JSON(400, gin.H{"error": "Missing incident ID"})
			return
		}

		inc, err := svc.GetByID(id)
		if err != nil {
			if errors.Is(err, ErrNotFound) {
				c.JSON(404, gin.H{"error": err.Error()})
				return
			}
			c.JSON(500, gin.H{"error": "Internal server error"})
			return
		}

		c.JSON(200, inc)
	}
}

// UpdateIncidentStatusHandler handles PATCH /api/v1/incidents/:id/status
func UpdateIncidentStatusHandler(svc *IncidentService) gin.HandlerFunc {
	return func(c *gin.Context) {
		id := c.Param("id")
		if id == "" {
			c.JSON(400, gin.H{"error": "Missing incident ID"})
			return
		}

		var req UpdateStatusRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(400, gin.H{"error": err.Error()})
			return
		}

		inc, err := svc.UpdateStatus(id, req)
		if err != nil {
			if errors.Is(err, ErrNotFound) {
				c.JSON(404, gin.H{"error": err.Error()})
				return
			}
			if errors.Is(err, ErrInvalidStatus) {
				c.JSON(400, gin.H{"error": err.Error()})
				return
			}
			c.JSON(500, gin.H{"error": "Internal server error"})
			return
		}

		c.JSON(200, inc)
	}
}

// InboundSMSHandler handles Africa's Talking POST /api/v1/sms/inbound
func InboundSMSHandler(svc *IncidentService) gin.HandlerFunc {
	return func(c *gin.Context) {
		from := c.PostForm("from")
		text := c.PostForm("text")

		log.Printf("Received inbound SMS from=%s, text=%q", from, text)

		tokens := strings.Fields(text)
		if len(tokens) < 2 {
			log.Printf("SMS format ignored (fewer than 2 tokens): %q", text)
			c.JSON(200, gin.H{"status": "ignored", "reason": "too few tokens"})
			return
		}

		// Parse IncidentType (first token)
		incType := IncidentType(strings.ToLower(tokens[0]))
		if !isValidIncidentType(incType) {
			log.Printf("SMS format ignored (invalid incident type): %q", tokens[0])
			c.JSON(200, gin.H{"status": "ignored", "reason": "invalid incident type"})
			return
		}

		// Parse Location (second token)
		locationName := tokens[1]

		// Parse optional Severity (third token) and Description (everything else)
		var severity SeverityLevel = SeverityModerate
		var description string

		if len(tokens) >= 3 {
			thirdLower := strings.ToLower(tokens[2])
			if thirdLower == "critical" || thirdLower == "moderate" || thirdLower == "stable" {
				severity = SeverityLevel(thirdLower)
				if len(tokens) > 3 {
					description = strings.Join(tokens[3:], " ")
				}
			} else {
				severity = SeverityModerate
				description = strings.Join(tokens[2:], " ")
			}
		}

		report := SMSReport{
			From:         from,
			Type:         incType,
			LocationName: locationName,
			Severity:     severity,
			Description:  description,
		}

		inc, err := svc.CreateFromSMS(report)
		if err != nil {
			log.Printf("Failed to create incident from SMS: %v", err)
			c.JSON(500, gin.H{"error": "Failed to store SMS incident"})
			return
		}

		c.JSON(201, inc)
	}
}

func main() {
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("DATABASE_URL environment variable is required")
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	db, err := NewDB(dbURL)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer db.Close()

	svc := NewIncidentService(db)

	r := gin.Default()
	r.Use(CORSMiddleware())

	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "OK"})
	})

	v1 := r.Group("/api/v1")
	{
		v1.POST("/incidents", CreateIncidentHandler(svc))
		v1.GET("/incidents/nearby", GetNearbyIncidentsHandler(svc))
		v1.GET("/incidents/recent", GetRecentIncidentsHandler(svc))
		v1.GET("/incidents/:id", GetIncidentByIDHandler(svc))
		v1.PATCH("/incidents/:id/status", UpdateIncidentStatusHandler(svc))
		v1.POST("/sms/inbound", InboundSMSHandler(svc))
	}

	log.Printf("Starting KaaRada Incident Service on port %s...", port)
	if err := r.Run(":" + port); err != nil {
		log.Fatalf("Failed to run HTTP server: %v", err)
	}
}
