package main

import (
	"encoding/json"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

// EventType identifies what kind of push event this is.
type EventType string

const (
	EventIncidentCreated EventType = "incident_created"
	EventStatusUpdated   EventType = "status_updated"
	EventPing            EventType = "ping"
)

// Event is the envelope sent to every connected client.
type Event struct {
	Type      EventType   `json:"type"`
	Payload   interface{} `json:"payload"`
	Timestamp time.Time   `json:"timestamp"`
}

// client represents a single connected WebSocket consumer.
type client struct {
	conn *websocket.Conn
	send chan []byte
}

// Hub maintains the set of active clients and broadcasts messages.
type Hub struct {
	mu      sync.RWMutex
	clients map[*client]bool

	broadcast  chan []byte
	register   chan *client
	unregister chan *client
}

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	// Allow all origins for hackathon — tighten for production
	CheckOrigin: func(r *http.Request) bool { return true },
}

// NewHub creates and starts a Hub. Call this once at startup.
func NewHub() *Hub {
	h := &Hub{
		clients:    make(map[*client]bool),
		broadcast:  make(chan []byte, 256),
		register:   make(chan *client),
		unregister: make(chan *client),
	}
	go h.run()
	return h
}

// run is the hub's event loop — single goroutine owns the clients map.
func (h *Hub) run() {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case c := <-h.register:
			h.mu.Lock()
			h.clients[c] = true
			h.mu.Unlock()
			log.Printf("[WS] client connected  (total: %d)", len(h.clients))

		case c := <-h.unregister:
			h.mu.Lock()
			if _, ok := h.clients[c]; ok {
				delete(h.clients, c)
				close(c.send)
			}
			h.mu.Unlock()
			log.Printf("[WS] client disconnected (total: %d)", len(h.clients))

		case msg := <-h.broadcast:
			h.mu.RLock()
			for c := range h.clients {
				select {
				case c.send <- msg:
				default:
					// Slow client — drop and clean up
					close(c.send)
					delete(h.clients, c)
				}
			}
			h.mu.RUnlock()

		case <-ticker.C:
			// Keep-alive ping so browsers don't close idle connections
			h.Broadcast(EventPing, map[string]string{"message": "keep-alive"})
		}
	}
}

// Broadcast serialises an event and sends it to every connected client.
func (h *Hub) Broadcast(eventType EventType, payload interface{}) {
	evt := Event{
		Type:      eventType,
		Payload:   payload,
		Timestamp: time.Now().UTC(),
	}
	data, err := json.Marshal(evt)
	if err != nil {
		log.Printf("[WS] marshal error: %v", err)
		return
	}
	h.broadcast <- data
	log.Printf("[WS] broadcast %s to clients", eventType)
}

// ConnectedClients returns how many clients are currently connected.
func (h *Hub) ConnectedClients() int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.clients)
}

// ServeWS upgrades an HTTP connection to WebSocket and registers it.
// Mount this as the GET /api/ws handler.
func (h *Hub) ServeWS(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("[WS] upgrade error: %v", err)
		return
	}

	c := &client{conn: conn, send: make(chan []byte, 256)}
	h.register <- c

	// Send a welcome event immediately so the client knows it's connected
	welcome := Event{
		Type:      "connected",
		Payload:   map[string]interface{}{"message": "Emergency API connected", "clients": h.ConnectedClients()},
		Timestamp: time.Now().UTC(),
	}
	if data, err := json.Marshal(welcome); err == nil {
		c.send <- data
	}

	// Two goroutines per connection: one reads (detects disconnect), one writes
	go c.writePump(h)
	go c.readPump(h)
}

// writePump pushes queued messages to the WebSocket connection.
func (c *client) writePump(h *Hub) {
	ticker := time.NewTicker(54 * time.Second)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()

	for {
		select {
		case msg, ok := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if !ok {
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := c.conn.WriteMessage(websocket.TextMessage, msg); err != nil {
				return
			}
		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

// readPump reads from the connection to detect disconnects.
func (c *client) readPump(h *Hub) {
	defer func() {
		h.unregister <- c
		c.conn.Close()
	}()

	c.conn.SetReadLimit(512)
	c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	c.conn.SetPongHandler(func(string) error {
		c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		return nil
	})

	for {
		_, _, err := c.conn.ReadMessage()
		if err != nil {
			break
		}
	}
}
