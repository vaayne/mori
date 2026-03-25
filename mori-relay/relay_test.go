package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// Helper to create a relay without the background cleanup goroutine.
func newTestRelay() *Relay {
	return &Relay{
		tokens:   make(map[string]*tokenEntry),
		sessions: make(map[string]*sessionEntry),
		rates:    make(map[string]*rateEntry),
	}
}

// --- Token generation and pairing flow ---

func TestHandlePairReturnsToken(t *testing.T) {
	r := newTestRelay()
	req := httptest.NewRequest(http.MethodPost, "/pair", nil)
	w := httptest.NewRecorder()

	r.HandlePair(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var resp map[string]string
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	token, ok := resp["token"]
	if !ok || token == "" {
		t.Fatal("response missing token")
	}

	// Token should exist in relay
	r.mu.Lock()
	_, exists := r.tokens[token]
	r.mu.Unlock()
	if !exists {
		t.Fatal("token not stored in relay")
	}
}

func TestPairHostCreatesSession(t *testing.T) {
	r := newTestRelay()

	// Create a token
	token := generateToken()
	r.tokens[token] = &tokenEntry{createdAt: time.Now()}

	p := &peer{} // No real connection needed for unit test
	sid, ok := r.pair(token, "host", p)
	if !ok {
		t.Fatal("pair(host) should succeed")
	}
	if sid == "" {
		t.Fatal("pair(host) should return session ID")
	}

	// Token should be consumed
	r.mu.Lock()
	_, tokenExists := r.tokens[token]
	sess, sessExists := r.sessions[sid]
	r.mu.Unlock()

	if tokenExists {
		t.Fatal("token should be consumed after host pairs")
	}
	if !sessExists {
		t.Fatal("session should be created")
	}
	if sess.host != p {
		t.Fatal("session should reference the host peer")
	}
}

func TestPairViewerAfterHost(t *testing.T) {
	r := newTestRelay()

	// Create token and pair host
	token := generateToken()
	r.tokens[token] = &tokenEntry{createdAt: time.Now()}
	hostPeer := &peer{}
	sid, ok := r.pair(token, "host", hostPeer)
	if !ok {
		t.Fatal("host pair should succeed")
	}

	// Create another token for viewer (since original is consumed)
	viewerToken := generateToken()
	r.tokens[viewerToken] = &tokenEntry{
		createdAt: time.Now(),
		host:      hostPeer,
	}
	// Link the token's host to the session's host so viewer lookup works
	r.mu.Lock()
	r.tokens[viewerToken].host = r.sessions[sid].host
	r.mu.Unlock()

	viewerPeer := &peer{}
	viewerSID, ok := r.pair(viewerToken, "viewer", viewerPeer)
	if !ok {
		t.Fatal("viewer pair should succeed")
	}
	if viewerSID != sid {
		t.Fatalf("viewer should join same session: got %s, want %s", viewerSID, sid)
	}

	r.mu.Lock()
	if r.sessions[sid].viewer != viewerPeer {
		t.Fatal("session should reference the viewer peer")
	}
	r.mu.Unlock()
}

func TestPairViewerWithoutHostFails(t *testing.T) {
	r := newTestRelay()

	token := generateToken()
	r.tokens[token] = &tokenEntry{createdAt: time.Now()}

	_, ok := r.pair(token, "viewer", &peer{})
	if ok {
		t.Fatal("viewer pair should fail when no host has connected")
	}
}

func TestPairDuplicateHostFails(t *testing.T) {
	r := newTestRelay()

	token := generateToken()
	r.tokens[token] = &tokenEntry{createdAt: time.Now()}

	// First host succeeds
	_, ok := r.pair(token, "host", &peer{})
	if ok {
		// Token is consumed, so second attempt with same token fails
	}

	// Second host with same token should fail (token consumed)
	_, ok = r.pair(token, "host", &peer{})
	if ok {
		t.Fatal("second host pair with consumed token should fail")
	}
}

// --- Token expiry ---

func TestPairExpiredTokenRejected(t *testing.T) {
	r := newTestRelay()

	token := generateToken()
	r.tokens[token] = &tokenEntry{
		createdAt: time.Now().Add(-tokenExpiry - time.Second),
	}

	_, ok := r.pair(token, "host", &peer{})
	if ok {
		t.Fatal("pair with expired token should fail")
	}

	// Token should be cleaned up
	r.mu.Lock()
	_, exists := r.tokens[token]
	r.mu.Unlock()
	if exists {
		t.Fatal("expired token should be deleted")
	}
}

// --- Rate limiting ---

func TestRateLimitAllowsUpToLimit(t *testing.T) {
	r := newTestRelay()
	ip := "192.168.1.1:12345"

	r.mu.Lock()
	for i := 0; i < pairRateLimit; i++ {
		if !r.checkRate(ip) {
			r.mu.Unlock()
			t.Fatalf("request %d should be allowed", i+1)
		}
	}
	r.mu.Unlock()
}

func TestRateLimitRejectsOverLimit(t *testing.T) {
	r := newTestRelay()
	ip := "192.168.1.1:12345"

	r.mu.Lock()
	for i := 0; i < pairRateLimit; i++ {
		r.checkRate(ip)
	}
	allowed := r.checkRate(ip)
	r.mu.Unlock()

	if allowed {
		t.Fatal("request exceeding rate limit should be rejected")
	}
}

func TestRateLimitReturns429(t *testing.T) {
	r := newTestRelay()

	// Exhaust rate limit
	r.mu.Lock()
	ip := "192.0.2.1:1234"
	r.rates[ip] = &rateEntry{count: pairRateLimit + 1, resetAt: time.Now().Add(time.Minute)}
	r.mu.Unlock()

	req := httptest.NewRequest(http.MethodPost, "/pair", nil)
	req.RemoteAddr = ip
	w := httptest.NewRecorder()

	r.HandlePair(w, req)

	if w.Code != http.StatusTooManyRequests {
		t.Fatalf("expected 429, got %d", w.Code)
	}
}

func TestRateLimitResetsAfterWindow(t *testing.T) {
	r := newTestRelay()
	ip := "10.0.0.1:5555"

	// Set expired rate entry
	r.mu.Lock()
	r.rates[ip] = &rateEntry{count: pairRateLimit + 10, resetAt: time.Now().Add(-time.Second)}
	allowed := r.checkRate(ip)
	r.mu.Unlock()

	if !allowed {
		t.Fatal("request after rate window reset should be allowed")
	}
}

// --- Session reconnection ---

func TestReconnectWithValidSession(t *testing.T) {
	r := newTestRelay()

	sid := generateToken()
	originalHost := &peer{}
	r.sessions[sid] = &sessionEntry{
		host:      originalHost,
		sessionID: sid,
		lastSeen:  time.Now(),
	}

	newHost := &peer{}
	ok := r.reconnect(sid, "host", newHost)
	if !ok {
		t.Fatal("reconnect should succeed for valid session")
	}

	r.mu.Lock()
	if r.sessions[sid].host != newHost {
		t.Fatal("host peer should be updated after reconnect")
	}
	r.mu.Unlock()
}

func TestReconnectViewerRole(t *testing.T) {
	r := newTestRelay()

	sid := generateToken()
	r.sessions[sid] = &sessionEntry{
		host:      &peer{},
		sessionID: sid,
		lastSeen:  time.Now(),
	}

	newViewer := &peer{}
	ok := r.reconnect(sid, "viewer", newViewer)
	if !ok {
		t.Fatal("viewer reconnect should succeed")
	}

	r.mu.Lock()
	if r.sessions[sid].viewer != newViewer {
		t.Fatal("viewer peer should be updated after reconnect")
	}
	r.mu.Unlock()
}

func TestReconnectExpiredSessionFails(t *testing.T) {
	r := newTestRelay()

	sid := generateToken()
	r.sessions[sid] = &sessionEntry{
		host:      &peer{},
		sessionID: sid,
		lastSeen:  time.Now().Add(-sessionTTL - time.Second),
	}

	ok := r.reconnect(sid, "host", &peer{})
	if ok {
		t.Fatal("reconnect should fail for expired session")
	}

	// Session should be cleaned up
	r.mu.Lock()
	_, exists := r.sessions[sid]
	r.mu.Unlock()
	if exists {
		t.Fatal("expired session should be deleted on reconnect attempt")
	}
}

func TestReconnectUnknownSessionFails(t *testing.T) {
	r := newTestRelay()

	ok := r.reconnect("nonexistent", "host", &peer{})
	if ok {
		t.Fatal("reconnect should fail for unknown session")
	}
}

// --- Cleanup of expired tokens/sessions ---

func TestCleanupExpiredTokens(t *testing.T) {
	r := newTestRelay()

	fresh := generateToken()
	expired := generateToken()
	r.tokens[fresh] = &tokenEntry{createdAt: time.Now()}
	r.tokens[expired] = &tokenEntry{createdAt: time.Now().Add(-tokenExpiry - time.Minute)}

	// Simulate what cleanupLoop does
	r.mu.Lock()
	now := time.Now()
	for k, v := range r.tokens {
		if now.Sub(v.createdAt) > tokenExpiry {
			delete(r.tokens, k)
		}
	}
	r.mu.Unlock()

	r.mu.Lock()
	defer r.mu.Unlock()

	if _, ok := r.tokens[fresh]; !ok {
		t.Fatal("fresh token should survive cleanup")
	}
	if _, ok := r.tokens[expired]; ok {
		t.Fatal("expired token should be removed by cleanup")
	}
}

func TestCleanupExpiredSessions(t *testing.T) {
	r := newTestRelay()

	activeSID := generateToken()
	expiredSID := generateToken()
	r.sessions[activeSID] = &sessionEntry{
		sessionID: activeSID,
		lastSeen:  time.Now(),
	}
	r.sessions[expiredSID] = &sessionEntry{
		sessionID: expiredSID,
		lastSeen:  time.Now().Add(-sessionTTL * 3),
	}

	// Simulate cleanup
	r.mu.Lock()
	now := time.Now()
	for k, v := range r.sessions {
		if now.Sub(v.lastSeen) > sessionTTL*2 {
			delete(r.sessions, k)
		}
	}
	r.mu.Unlock()

	r.mu.Lock()
	defer r.mu.Unlock()

	if _, ok := r.sessions[activeSID]; !ok {
		t.Fatal("active session should survive cleanup")
	}
	if _, ok := r.sessions[expiredSID]; ok {
		t.Fatal("expired session should be removed by cleanup")
	}
}

func TestCleanupExpiredRates(t *testing.T) {
	r := newTestRelay()

	r.rates["active"] = &rateEntry{count: 5, resetAt: time.Now().Add(time.Minute)}
	r.rates["expired"] = &rateEntry{count: 5, resetAt: time.Now().Add(-time.Second)}

	// Simulate cleanup
	r.mu.Lock()
	for k, v := range r.rates {
		if time.Now().After(v.resetAt) {
			delete(r.rates, k)
		}
	}
	r.mu.Unlock()

	r.mu.Lock()
	defer r.mu.Unlock()

	if _, ok := r.rates["active"]; !ok {
		t.Fatal("active rate entry should survive cleanup")
	}
	if _, ok := r.rates["expired"]; ok {
		t.Fatal("expired rate entry should be removed by cleanup")
	}
}
