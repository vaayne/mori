import Foundation
import MoriRemoteProtocol

/// WebSocket client actor that connects to the Mori relay as a viewer.
///
/// Manages the full connection lifecycle using the MoriRemoteProtocol state machine:
/// `disconnected -> pairing -> connected -> attached -> detached`
///
/// Binary WebSocket frames carry terminal data; JSON text frames carry control messages.
/// Integrates with `PipeBridge` for ghostty rendering.
actor RelayClient {

    // MARK: - State

    private(set) var state: ConnectionState = .disconnected
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var sessionID: String?
    private var receiveTask: Task<Void, Never>?

    /// Reconnection state
    private var reconnectAttempt: Int = 0
    private static let maxReconnectAttempts = 10
    private static let baseReconnectDelay: TimeInterval = 1.0
    private static let maxReconnectDelay: TimeInterval = 30.0

    /// Saved connection parameters for reconnection
    private var savedRelayURL: String?
    private var savedToken: String?

    // MARK: - Callbacks

    /// Called when binary terminal data arrives from the relay (to be written to ghostty).
    private(set) var onTerminalData: (@Sendable (Data) async -> Void)?

    /// Called when a control message arrives from the relay.
    private(set) var onControlMessage: (@Sendable (ControlMessage) -> Void)?

    /// Called when the connection state changes.
    private(set) var onStateChange: (@Sendable (ConnectionState) -> Void)?

    /// Set the terminal data callback (binary frames from relay -> ghostty).
    func setOnTerminalData(_ callback: (@Sendable (Data) async -> Void)?) {
        self.onTerminalData = callback
    }

    /// Set the control message callback.
    func setOnControlMessage(_ callback: (@Sendable (ControlMessage) -> Void)?) {
        self.onControlMessage = callback
    }

    /// Set the state change callback.
    func setOnStateChange(_ callback: (@Sendable (ConnectionState) -> Void)?) {
        self.onStateChange = callback
    }

    // MARK: - Init

    init() {
        // Load stored session ID from Keychain
        self.sessionID = KeychainStore.loadSessionID()
    }

    // MARK: - Public API

    /// Connect to the relay as a viewer.
    /// - Parameters:
    ///   - relayURL: WebSocket endpoint URL (e.g., `wss://relay.example.com/ws`)
    ///   - token: One-time pairing token (used for initial pairing)
    func connect(relayURL: String, token: String) async throws {
        savedRelayURL = relayURL
        savedToken = token
        reconnectAttempt = 0
        try await establishConnection(relayURL: relayURL, token: token)
    }

    /// Reconnect using stored session ID. Returns false if no session ID available.
    @discardableResult
    func reconnect() async -> Bool {
        guard let relayURL = savedRelayURL else {
            NSLog("[RelayClient] No saved relay URL for reconnect")
            return false
        }

        // Prefer session ID for reconnection (no token needed)
        guard sessionID != nil || savedToken != nil else {
            NSLog("[RelayClient] No session ID or token for reconnect")
            return false
        }

        do {
            try await establishConnection(
                relayURL: relayURL,
                token: savedToken ?? ""
            )
            return true
        } catch {
            NSLog("[RelayClient] Reconnect failed: \(error)")
            return false
        }
    }

    /// Disconnect cleanly, optionally sending a detach message.
    func disconnect(reason: String? = nil) async {
        // Send detach if we're attached
        if case .attached = state {
            let detach = ControlMessage.detach(ControlMessage.Detach(reason: reason))
            try? await sendControlMessage(detach)
        }

        // Cancel receive loop
        receiveTask?.cancel()
        receiveTask = nil

        // Close WebSocket
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil

        transitionState(to: .disconnected)
    }

    /// Send a control message to the relay.
    func sendControlMessage(_ message: ControlMessage) async throws {
        let data = try encodeMessage(message)
        guard let text = String(data: data, encoding: .utf8) else {
            throw RelayClientError.encodingFailed
        }
        try await webSocketTask?.send(.string(text))
    }

    /// Send binary terminal input data to the relay.
    func sendTerminalData(_ data: Data) async throws {
        try await webSocketTask?.send(.data(data))
    }

    /// Invalidate the stored session ID (unpair).
    func invalidateSession() {
        sessionID = nil
        KeychainStore.deleteSessionID()
        savedRelayURL = nil
        savedToken = nil
    }

    /// Whether we have a stored session ID for reconnection.
    var hasStoredSession: Bool {
        sessionID != nil
    }

    // MARK: - Connection

    private func establishConnection(relayURL: String, token: String) async throws {
        guard var components = URLComponents(string: relayURL) else {
            throw RelayClientError.invalidURL(relayURL)
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "role", value: Role.viewer.rawValue))

        // Use session_id for reconnection if available, otherwise use token
        if let sessionID {
            queryItems.append(URLQueryItem(name: "session_id", value: sessionID))
        } else if !token.isEmpty {
            queryItems.append(URLQueryItem(name: "token", value: token))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw RelayClientError.invalidURL(relayURL)
        }

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 30

        let session = URLSession(configuration: config)
        let task = session.webSocketTask(with: url)
        task.resume()

        self.urlSession = session
        self.webSocketTask = task

        transitionState(to: .pairing)

        // Send handshake
        let handshake = ControlMessage.handshake(
            ControlMessage.Handshake(role: .viewer)
        )
        try await sendControlMessage(handshake)

        transitionState(to: .connected)
        reconnectAttempt = 0

        NSLog("[RelayClient] Connected to relay")

        // Start receive loop
        startReceiveLoop()
    }

    // MARK: - Receive Loop

    private func startReceiveLoop() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    private func receiveLoop() async {
        guard let task = webSocketTask else { return }

        while !Task.isCancelled {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await task.receive()
            } catch {
                if !Task.isCancelled {
                    NSLog("[RelayClient] WebSocket receive error: \(error.localizedDescription)")
                    await handleDisconnect()
                }
                return
            }

            switch message {
            case .string(let text):
                await handleTextFrame(text)
            case .data(let data):
                await onTerminalData?(data)
            @unknown default:
                break
            }
        }
    }

    private func handleTextFrame(_ text: String) async {
        guard let data = text.data(using: .utf8) else { return }

        do {
            let message = try decodeMessage(data)

            switch message {
            case .handshake(let hs):
                // Extract session_id from capabilities (relay sends it after pairing)
                if let sid = hs.capabilities.first(where: { $0.hasPrefix("session_id:") }) {
                    let newSessionID = String(sid.dropFirst("session_id:".count))
                    self.sessionID = newSessionID
                    try? KeychainStore.saveSessionID(newSessionID)
                    NSLog("[RelayClient] Session ID stored")
                }

            case .heartbeat(let heartbeat):
                // Respond with pong (echo heartbeat back)
                let pong = ControlMessage.heartbeat(
                    ControlMessage.Heartbeat(timestamp: heartbeat.timestamp)
                )
                try await sendControlMessage(pong)

            case .error(let err):
                NSLog("[RelayClient] Relay error: \(err.code.rawValue) - \(err.message)")
                if err.code == .tokenExpired || err.code == .tokenInvalid {
                    // Session expired — invalidate and require re-pairing
                    invalidateSession()
                    await disconnect(reason: "session expired")
                }

            default:
                break
            }

            // Forward all control messages to the callback
            onControlMessage?(message)

        } catch {
            NSLog("[RelayClient] Failed to decode control message: \(error)")
        }
    }

    // MARK: - Disconnect & Reconnect

    private func handleDisconnect() async {
        transitionState(to: .disconnected)

        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil

        // Attempt reconnection with exponential backoff
        guard savedRelayURL != nil else { return }
        guard reconnectAttempt < Self.maxReconnectAttempts else {
            NSLog("[RelayClient] Max reconnect attempts reached")
            return
        }

        reconnectAttempt += 1
        let delay = reconnectDelay()
        NSLog("[RelayClient] Reconnecting in \(String(format: "%.1f", delay))s (attempt \(reconnectAttempt)/\(Self.maxReconnectAttempts))")

        do {
            try await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await reconnect()
        } catch {
            NSLog("[RelayClient] Reconnect sleep cancelled")
        }
    }

    /// Exponential backoff with jitter.
    private func reconnectDelay() -> TimeInterval {
        let base = Self.baseReconnectDelay * pow(2.0, Double(reconnectAttempt - 1))
        let capped = min(base, Self.maxReconnectDelay)
        let jitter = Double.random(in: 0...(capped * 0.1))
        return capped + jitter
    }

    // MARK: - State Machine

    private func transitionState(to newState: ConnectionState) {
        if let valid = state.transition(to: newState) {
            state = valid
            onStateChange?(valid)
        } else {
            NSLog("[RelayClient] Invalid state transition: \(state) -> \(newState)")
        }
    }
}

// MARK: - Errors

enum RelayClientError: Error, CustomStringConvertible {
    case invalidURL(String)
    case encodingFailed
    case notConnected

    var description: String {
        switch self {
        case .invalidURL(let url): "Invalid relay URL: \(url)"
        case .encodingFailed: "Failed to encode control message"
        case .notConnected: "Not connected to relay"
        }
    }
}
