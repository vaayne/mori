import Foundation
import MoriRemoteProtocol

// =============================================================================
// Reconnect State Machine Tests
// =============================================================================
// Tests for ConnectionState transitions covering:
// - Valid transitions
// - Invalid transitions
// - Disconnect scenarios
// - Background/foreground lifecycle
// - Session expiry and re-pair flows
// =============================================================================

print("--- ConnectionState Transition Tests ---")

// MARK: - Valid Transitions

print("  Valid transitions...")

// disconnected -> pairing
do {
    let state = ConnectionState.disconnected
    let next = state.transition(to: .pairing)
    assertEqual(next, .pairing, "disconnected -> pairing should succeed")
}

// disconnected -> connected (reconnect with session_id, skip pairing)
do {
    let state = ConnectionState.disconnected
    let next = state.transition(to: .connected)
    assertEqual(next, .connected, "disconnected -> connected should succeed")
}

// pairing -> connected
do {
    let state = ConnectionState.pairing
    let next = state.transition(to: .connected)
    assertEqual(next, .connected, "pairing -> connected should succeed")
}

// pairing -> disconnected (pairing failed)
do {
    let state = ConnectionState.pairing
    let next = state.transition(to: .disconnected)
    assertEqual(next, .disconnected, "pairing -> disconnected should succeed")
}

// connected -> attached
do {
    let state = ConnectionState.connected
    let next = state.transition(to: .attached(sessionName: "test"))
    assertEqual(next, .attached(sessionName: "test"), "connected -> attached should succeed")
}

// connected -> disconnected
do {
    let state = ConnectionState.connected
    let next = state.transition(to: .disconnected)
    assertEqual(next, .disconnected, "connected -> disconnected should succeed")
}

// attached -> detached
do {
    let state = ConnectionState.attached(sessionName: "test")
    let next = state.transition(to: .detached)
    assertEqual(next, .detached, "attached -> detached should succeed")
}

// attached -> disconnected (connection lost while attached)
do {
    let state = ConnectionState.attached(sessionName: "test")
    let next = state.transition(to: .disconnected)
    assertEqual(next, .disconnected, "attached -> disconnected should succeed")
}

// detached -> attached (re-attach to same or different session)
do {
    let state = ConnectionState.detached
    let next = state.transition(to: .attached(sessionName: "other"))
    assertEqual(next, .attached(sessionName: "other"), "detached -> attached should succeed")
}

// detached -> connected (back to session selection)
do {
    let state = ConnectionState.detached
    let next = state.transition(to: .connected)
    assertEqual(next, .connected, "detached -> connected should succeed")
}

// detached -> disconnected
do {
    let state = ConnectionState.detached
    let next = state.transition(to: .disconnected)
    assertEqual(next, .disconnected, "detached -> disconnected should succeed")
}

// MARK: - Invalid Transitions

print("  Invalid transitions...")

// disconnected -> attached (must go through connected first)
do {
    let state = ConnectionState.disconnected
    let next = state.transition(to: .attached(sessionName: "test"))
    assertNil(next, "disconnected -> attached should fail")
}

// disconnected -> detached
do {
    let state = ConnectionState.disconnected
    let next = state.transition(to: .detached)
    assertNil(next, "disconnected -> detached should fail")
}

// pairing -> attached (must go through connected first)
do {
    let state = ConnectionState.pairing
    let next = state.transition(to: .attached(sessionName: "test"))
    assertNil(next, "pairing -> attached should fail")
}

// connected -> pairing
do {
    let state = ConnectionState.connected
    let next = state.transition(to: .pairing)
    assertNil(next, "connected -> pairing should fail")
}

// connected -> detached (must go through attached first)
do {
    let state = ConnectionState.connected
    let next = state.transition(to: .detached)
    assertNil(next, "connected -> detached should fail")
}

// attached -> connected (must go through detached first)
do {
    let state = ConnectionState.attached(sessionName: "test")
    let next = state.transition(to: .connected)
    assertNil(next, "attached -> connected should fail")
}

// attached -> pairing
do {
    let state = ConnectionState.attached(sessionName: "test")
    let next = state.transition(to: .pairing)
    assertNil(next, "attached -> pairing should fail")
}

// MARK: - Disconnect Scenario

print("  Disconnect scenario...")

// Simulate: connect -> attach -> connection lost -> reconnect -> re-attach
do {
    var state = ConnectionState.disconnected

    // Connect (pairing)
    state = state.transition(to: .pairing) ?? state
    assertEqual(state, .pairing, "step 1: pairing")

    // Paired
    state = state.transition(to: .connected) ?? state
    assertEqual(state, .connected, "step 2: connected")

    // Attach to session
    state = state.transition(to: .attached(sessionName: "mori/main")) ?? state
    assertEqual(state, .attached(sessionName: "mori/main"), "step 3: attached")

    // Connection lost
    state = state.transition(to: .disconnected) ?? state
    assertEqual(state, .disconnected, "step 4: disconnected")

    // Reconnect (with session_id, skip pairing)
    state = state.transition(to: .connected) ?? state
    assertEqual(state, .connected, "step 5: reconnected")

    // Re-attach
    state = state.transition(to: .attached(sessionName: "mori/main")) ?? state
    assertEqual(state, .attached(sessionName: "mori/main"), "step 6: re-attached")
}

// MARK: - Background/Foreground Lifecycle

print("  Background/foreground lifecycle...")

// Simulate: attached -> background (detach) -> foreground (reconnect + re-attach)
do {
    var state = ConnectionState.disconnected

    // Initial connection
    state = state.transition(to: .connected) ?? state
    state = state.transition(to: .attached(sessionName: "mori/main")) ?? state
    assertEqual(state, .attached(sessionName: "mori/main"), "initial attached")

    // App goes to background: detach then disconnect
    state = state.transition(to: .detached) ?? state
    assertEqual(state, .detached, "detached on background")

    state = state.transition(to: .disconnected) ?? state
    assertEqual(state, .disconnected, "disconnected on background")

    // App comes to foreground: reconnect
    state = state.transition(to: .connected) ?? state
    assertEqual(state, .connected, "reconnected on foreground")

    // Re-attach
    state = state.transition(to: .attached(sessionName: "mori/main")) ?? state
    assertEqual(state, .attached(sessionName: "mori/main"), "re-attached on foreground")
}

// MARK: - Session Expiry + Re-pair

print("  Session expiry + re-pair...")

// Simulate: reconnect fails (session expired) -> re-pair from scratch
do {
    var state = ConnectionState.disconnected

    // Attempt reconnect with expired session_id
    // The relay would respond with error -> disconnect
    state = state.transition(to: .pairing) ?? state
    assertEqual(state, .pairing, "attempt reconnect via pairing")

    // Relay rejects with token_expired -> back to disconnected
    state = state.transition(to: .disconnected) ?? state
    assertEqual(state, .disconnected, "rejected, back to disconnected")

    // User scans new QR code -> fresh pairing
    state = state.transition(to: .pairing) ?? state
    assertEqual(state, .pairing, "fresh pairing")

    state = state.transition(to: .connected) ?? state
    assertEqual(state, .connected, "paired successfully")

    state = state.transition(to: .attached(sessionName: "mori/feature")) ?? state
    assertEqual(state, .attached(sessionName: "mori/feature"), "attached to new session")
}

// MARK: - Detach and Switch Session

print("  Detach and switch session...")

do {
    var state = ConnectionState.disconnected

    state = state.transition(to: .connected) ?? state
    state = state.transition(to: .attached(sessionName: "mori/main")) ?? state
    assertEqual(state, .attached(sessionName: "mori/main"), "attached to main")

    // Detach from current session
    state = state.transition(to: .detached) ?? state
    assertEqual(state, .detached, "detached from main")

    // Attach to different session
    state = state.transition(to: .attached(sessionName: "mori/feature")) ?? state
    assertEqual(state, .attached(sessionName: "mori/feature"), "attached to feature")
}

// MARK: - Message Serialization Round-trip

print("--- Message Serialization Round-trip ---")

do {
    let messages: [ControlMessage] = [
        .handshake(.init(role: .viewer, capabilities: ["session_id:abc123"])),
        .sessionList(.init(sessions: [
            SessionInfo(name: "ws__mori__main", displayName: "mori/main", windowCount: 3, attached: true),
        ])),
        .attach(.init(sessionName: "ws__mori__main", mode: .readOnly)),
        .detach(.init(reason: "app backgrounded")),
        .resize(.init(cols: 80, rows: 24)),
        .modeChange(.init(mode: .interactive)),
        .heartbeat(.init(timestamp: 1234567890)),
        .error(.init(code: .tokenExpired, message: "Session expired")),
    ]

    for original in messages {
        let data = try encodeMessage(original)
        assertNotNil(String(data: data, encoding: .utf8), "encoded should be valid UTF-8")
        let decoded = try decodeMessage(data)
        // Verify round-trip by re-encoding and re-decoding
        let reEncoded = try encodeMessage(decoded)
        let reDecoded = try decodeMessage(reEncoded)
        // Compare re-encoded -> re-decoded with decoded (second encode stabilizes key order)
        let stableOriginal = try encodeMessage(decoded)
        let stableRoundTrip = try encodeMessage(reDecoded)
        assertEqual(stableOriginal, stableRoundTrip, "stable round-trip")
    }
}

// MARK: - Heartbeat timestamp preservation

print("  Heartbeat timestamp preservation...")

do {
    let ts: UInt64 = 1_711_234_567_890
    let hb = ControlMessage.heartbeat(.init(timestamp: ts))
    let data = try encodeMessage(hb)
    let decoded = try decodeMessage(data)
    if case .heartbeat(let payload) = decoded {
        assertEqual(payload.timestamp, ts, "heartbeat timestamp preserved")
    } else {
        assertTrue(false, "expected heartbeat message")
    }
}

// MARK: - Error code round-trip

print("  Error code round-trip...")

do {
    let codes: [ErrorCode] = [
        .versionMismatch, .sessionNotFound, .alreadyAttached,
        .tokenExpired, .tokenInvalid, .rateLimited, .internalError,
    ]
    for code in codes {
        let msg = ControlMessage.error(.init(code: code, message: "test"))
        let data = try encodeMessage(msg)
        let decoded = try decodeMessage(data)
        if case .error(let payload) = decoded {
            assertEqual(payload.code, code, "error code \(code.rawValue) round-trip")
        } else {
            assertTrue(false, "expected error message")
        }
    }
}

// MARK: - Results

print("")
printResults()
if failCount > 0 {
    exit(1)
}
