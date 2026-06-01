package main

import (
	"bytes"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"
)

// notifyIncidentCreated fires a non-blocking HTTP POST to the notification

func notifyIncidentCreated(inc *Incident) {
	url := os.Getenv("NOTIFY_SERVICE_URL")
	if url == "" {
		url = "http://localhost:8090/incidents"
	}

	go func() {
		body, err := json.Marshal(inc)
		if err != nil {
			log.Printf("[NOTIFY] marshal error: %v", err)
			return
		}

		client := &http.Client{Timeout: 3 * time.Second}
		resp, err := client.Post(url, "application/json", bytes.NewReader(body))
		if err != nil {
			log.Printf("[NOTIFY] notification service unreachable: %v", err)
			return
		}
		defer resp.Body.Close()
		log.Printf("[NOTIFY] notification service responded: %d", resp.StatusCode)
	}()
}
