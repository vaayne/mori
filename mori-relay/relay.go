package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"log"
	"net/http"
	"sync"
	"time"

	"nhooyr.io/websocket"
)

const (
	tokenExpiry       = 5 * time.Minute
	sessionTTL        = 2 * time.Minute
	heartbeatInterval = 30 * time.Second
	maxWriteBuffer    = 256 * 1024 // 256KB
	pairRateLimit     = 10         // per minute per IP
)

// Relay manages token pairing and WebSocket byte relaying.
type Relay struct {
	mu       sync.Mutex
	tokens   map[string]*tokenEntry   // token -> entry
	sessions map[string]*sessionEntry // sessionID -> entry
	rates    map[string]*rateEntry    // IP -> rate
}

type tokenEntry struct {
	createdAt time.Time
	host      *peer // set when host connects
}

type sessionEntry struct {
	host      *peer
	viewer    *peer
	lastSeen  time.Time
	sessionID string
}

type peer struct {
	conn   *websocket.Conn
	cancel context.CancelFunc
}

type rateEntry struct {
	count    int
	resetAt  time.Time
}

func NewRelay() *Relay {
	r := &Relay{
		tokens:   make(map[string]*tokenEntry),
		sessions: make(map[string]*sessionEntry),
		rates:    make(map[string]*rateEntry),
	}
	go r.cleanupLoop()
	return r
}

// HandlePair generates a one-time pairing token.
func (r *Relay) HandlePair(w http.ResponseWriter, req *http.Request) {
	ip := req.RemoteAddr

	r.mu.Lock()
	if !r.checkRate(ip) {
		r.mu.Unlock()
		http.Error(w, `{"error":"rate_limited"}`, http.StatusTooManyRequests)
		return
	}

	token := generateToken()
	r.tokens[token] = &tokenEntry{createdAt: time.Now()}
	r.mu.Unlock()

	log.Printf("pair: token created ip=%s", ip)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"token": token})
}

// HandleWS handles WebSocket connections for both host and viewer.
func (r *Relay) HandleWS(w http.ResponseWriter, req *http.Request) {
	token := req.URL.Query().Get("token")
	role := req.URL.Query().Get("role")
	sessionID := req.URL.Query().Get("session_id")

	if role != "host" && role != "viewer" {
		http.Error(w, `{"error":"invalid role"}`, http.StatusBadRequest)
		return
	}

	conn, err := websocket.Accept(w, req, &websocket.AcceptOptions{
		InsecureSkipVerify: true, // Allow any origin for native clients
	})
	if err != nil {
		log.Printf("ws: accept error: %v", err)
		return
	}
	conn.SetReadLimit(maxWriteBuffer)

	ctx, cancel := context.WithCancel(req.Context())
	p := &peer{conn: conn, cancel: cancel}

	// Try reconnect with session ID first
	if sessionID != "" {
		if r.reconnect(sessionID, role, p) {
			r.pipeSession(ctx, sessionID, role, p)
			return
		}
		// Session expired, fall through to token pairing
	}

	if token == "" {
		conn.Close(websocket.StatusPolicyViolation, "token or session_id required")
		cancel()
		return
	}

	sid, ok := r.pair(token, role, p)
	if !ok {
		conn.Close(websocket.StatusPolicyViolation, "invalid or expired token")
		cancel()
		return
	}

	// Send session ID to the connecting peer
	msg, _ := json.Marshal(map[string]string{
		"type":       "paired",
		"session_id": sid,
	})
	conn.Write(ctx, websocket.MessageText, msg)

	r.pipeSession(ctx, sid, role, p)
}

func (r *Relay) pair(token, role string, p *peer) (string, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()

	entry, ok := r.tokens[token]
	if !ok || time.Since(entry.createdAt) > tokenExpiry {
		delete(r.tokens, token)
		return "", false
	}

	if role == "host" {
		if entry.host != nil {
			return "", false // token already consumed by a host
		}
		entry.host = p

		// Generate session ID, create session
		sid := generateToken()
		r.sessions[sid] = &sessionEntry{
			host:      p,
			sessionID: sid,
			lastSeen:  time.Now(),
		}
		delete(r.tokens, token) // consumed
		log.Printf("pair: host paired sid=%s", sid[:8])
		return sid, true
	}

	// Viewer: need a host already paired with this token
	// Actually, viewer pairs with a different token or uses session_id.
	// For simplicity: token is consumed by host, viewer uses session_id.
	// But we also support both connecting with same token.
	if entry.host == nil {
		// Host hasn't connected yet — store viewer temporarily
		return "", false
	}

	sid := ""
	for id, s := range r.sessions {
		if s.host == entry.host {
			sid = id
			break
		}
	}
	if sid == "" {
		return "", false
	}

	r.sessions[sid].viewer = p
	r.sessions[sid].lastSeen = time.Now()
	delete(r.tokens, token)
	log.Printf("pair: viewer paired sid=%s", sid[:8])
	return sid, true
}

func (r *Relay) reconnect(sessionID, role string, p *peer) bool {
	r.mu.Lock()
	defer r.mu.Unlock()

	s, ok := r.sessions[sessionID]
	if !ok || time.Since(s.lastSeen) > sessionTTL {
		delete(r.sessions, sessionID)
		return false
	}

	if role == "host" {
		s.host = p
	} else {
		s.viewer = p
	}
	s.lastSeen = time.Now()
	log.Printf("reconnect: %s reconnected sid=%s", role, sessionID[:8])
	return true
}

func (r *Relay) pipeSession(ctx context.Context, sid, role string, self *peer) {
	defer self.conn.Close(websocket.StatusNormalClosure, "")
	defer self.cancel()

	for {
		msgType, data, err := self.conn.Read(ctx)
		if err != nil {
			log.Printf("pipe: %s read error sid=%s: %v", role, sid[:8], err)
			return
		}

		r.mu.Lock()
		s, ok := r.sessions[sid]
		if !ok {
			r.mu.Unlock()
			return
		}
		s.lastSeen = time.Now()

		var target *peer
		if role == "host" {
			target = s.viewer
		} else {
			target = s.host
		}
		r.mu.Unlock()

		if target == nil {
			continue // peer not connected yet
		}

		writeCtx, writeCancel := context.WithTimeout(ctx, 5*time.Second)
		err = target.conn.Write(writeCtx, msgType, data)
		writeCancel()
		if err != nil {
			log.Printf("pipe: %s write error sid=%s: %v", role, sid[:8], err)
			return
		}
	}
}

func (r *Relay) checkRate(ip string) bool {
	entry, ok := r.rates[ip]
	if !ok || time.Now().After(entry.resetAt) {
		r.rates[ip] = &rateEntry{count: 1, resetAt: time.Now().Add(time.Minute)}
		return true
	}
	entry.count++
	return entry.count <= pairRateLimit
}

func (r *Relay) cleanupLoop() {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	for range ticker.C {
		r.mu.Lock()
		now := time.Now()

		for k, v := range r.tokens {
			if now.Sub(v.createdAt) > tokenExpiry {
				if v.host != nil {
					v.host.conn.Close(websocket.StatusGoingAway, "token expired")
				}
				delete(r.tokens, k)
			}
		}

		for k, v := range r.sessions {
			if now.Sub(v.lastSeen) > sessionTTL*2 {
				delete(r.sessions, k)
			}
		}

		for k, v := range r.rates {
			if now.After(v.resetAt) {
				delete(r.rates, k)
			}
		}

		r.mu.Unlock()
	}
}

func generateToken() string {
	b := make([]byte, 16)
	rand.Read(b)
	return hex.EncodeToString(b)
}
