import Foundation
import MoriRemoteProtocol

/// Actor that manages the WebSocket connection to the relay and bridges
/// local tmux sessions via forkpty. Handles bidirectional byte streaming,
/// control messages, and session lifecycle.
actor RelayConnector {

    // MARK: - State

    private var state: ConnectionState = .disconnected
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var ptyBridge: PTYBridge?
    private var sessionID: String?
    private var currentSessionName: String?
    private var currentMode: SessionMode = .readOnly

    /// Grouped session tracker for cleanup
    private let groupedSessionManager = GroupedSessionManager()

    /// Reconnection state
    private var reconnectAttempt: Int = 0
    private static let maxReconnectAttempt = 10
    private static let baseReconnectDelay: TimeInterval = 1.0
    private static let maxReconnectDelay: TimeInterval = 60.0

    /// Saved connection parameters for reconnection
    private var savedRelayURL: String?
    private var savedToken: String?

    /// Continuation for runUntilDisconnected
    private var disconnectContinuation: CheckedContinuation<Void, any Error>?

    /// Whether we're running the event loop
    private var isRunning = false

    // MARK: - Public API

    /// Connect to the relay as a host.
    func connect(relayURL: String, token: String, sessionID: String? = nil) async throws {
        savedRelayURL = relayURL
        savedToken = token

        if let sessionID {
            self.sessionID = sessionID
        }

        try await establishConnection(relayURL: relayURL, token: token)
    }

    /// Run the connector event loop until the WebSocket disconnects or is cancelled.
    func runUntilDisconnected() async throws {
        isRunning = true
        defer { isRunning = false }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            self.disconnectContinuation = continuation
        }
    }

    /// Attach to a tmux session, bridging its pty to the WebSocket.
    func attachSession(name: String, mode: SessionMode) async throws {
        // Detach any existing session first
        if ptyBridge != nil {
            await detachCurrentSession()
        }

        currentSessionName = name
        currentMode = mode

        let tmuxCommand: [String]

        switch mode {
        case .readOnly:
            // Read-only: attach with -r flag (ignore-size)
            tmuxCommand = ["tmux", "attach-session", "-r", "-t", name]
        case .interactive:
            // Interactive: create a grouped session so iOS has independent window sizing
            let groupedName = try await groupedSessionManager.createGroupedSession(target: name)
            tmuxCommand = ["tmux", "attach-session", "-t", groupedName]
        }

        let bridge = try PTYBridge(command: tmuxCommand)
        self.ptyBridge = bridge

        // Start reading from pty and forwarding to WebSocket
        Task { [weak self] in
            await self?.ptyReadLoop(bridge: bridge)
        }

        // Notify the state change
        state = .attached(sessionName: name)
        print("[RelayConnector] Attached to session: \(name) (mode: \(mode.rawValue))")
    }

    /// Detach from the current tmux session.
    func detachCurrentSession() async {
        if let bridge = ptyBridge {
            bridge.terminate()
            ptyBridge = nil
        }

        // Clean up grouped session if in interactive mode
        if currentMode == .interactive, let sessionName = currentSessionName {
            await groupedSessionManager.cleanupGroupedSessions(for: sessionName)
        }

        currentSessionName = nil
        state = .detached
        print("[RelayConnector] Detached from session")
    }

    /// Send a control message to the relay.
    func sendControlMessage(_ message: ControlMessage) async throws {
        let data = try encodeMessage(message)
        guard let text = String(data: data, encoding: .utf8) else {
            throw RelayConnectorError.encodingFailed
        }
        try await webSocketTask?.send(.string(text))
    }

    /// Get the current connection state.
    func currentState() -> ConnectionState {
        state
    }

    /// Get the stored session ID for reconnection.
    func getSessionID() -> String? {
        sessionID
    }

    // MARK: - Connection

    private func establishConnection(relayURL: String, token: String) async throws {
        guard var components = URLComponents(string: relayURL) else {
            throw RelayConnectorError.invalidURL(relayURL)
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "token", value: token))
        queryItems.append(URLQueryItem(name: "role", value: Role.host.rawValue))
        if let sessionID {
            queryItems.append(URLQueryItem(name: "session_id", value: sessionID))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw RelayConnectorError.invalidURL(relayURL)
        }

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        task.resume()

        self.urlSession = session
        self.webSocketTask = task
        self.state = .pairing

        // Send handshake
        let handshake = ControlMessage.handshake(
            ControlMessage.Handshake(role: .host)
        )
        try await sendControlMessage(handshake)

        self.state = .connected
        self.reconnectAttempt = 0

        print("[RelayConnector] Connected to relay")

        // Start the receive loop
        Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    // MARK: - WebSocket Receive Loop

    private func receiveLoop() async {
        guard let task = webSocketTask else { return }

        while true {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await task.receive()
            } catch {
                print("[RelayConnector] WebSocket receive error: \(error.localizedDescription)")
                await handleDisconnect(error: error)
                return
            }

            switch message {
            case .string(let text):
                await handleControlMessage(text)
            case .data(let data):
                await handleTerminalData(data)
            @unknown default:
                break
            }
        }
    }

    private func handleControlMessage(_ text: String) async {
        guard let data = text.data(using: .utf8) else { return }

        do {
            let message = try decodeMessage(data)
            switch message {
            case .attach(let attach):
                try await attachSession(name: attach.sessionName, mode: attach.mode)

            case .detach:
                await detachCurrentSession()

            case .resize(let resize):
                ptyBridge?.resize(cols: resize.cols, rows: resize.rows)

            case .modeChange(let modeChange):
                if let sessionName = currentSessionName {
                    await detachCurrentSession()
                    try await attachSession(name: sessionName, mode: modeChange.mode)
                }

            case .sessionList:
                let lister = SessionLister()
                let sessions = try await lister.listSessions()
                let response = ControlMessage.sessionList(
                    ControlMessage.SessionList(sessions: sessions)
                )
                try await sendControlMessage(response)

            case .heartbeat(let heartbeat):
                // Respond with pong (echo heartbeat back)
                let pong = ControlMessage.heartbeat(
                    ControlMessage.Heartbeat(timestamp: heartbeat.timestamp)
                )
                try await sendControlMessage(pong)

            case .handshake(let hs):
                // Store session ID if provided in capabilities
                if let sid = hs.capabilities.first(where: { $0.hasPrefix("session_id:") }) {
                    self.sessionID = String(sid.dropFirst("session_id:".count))
                    print("[RelayConnector] Session ID: \(self.sessionID ?? "nil")")
                }

            case .error(let err):
                print("[RelayConnector] Relay error: \(err.code.rawValue) — \(err.message)")

            }
        } catch {
            print("[RelayConnector] Failed to decode control message: \(error)")
        }
    }

    private func handleTerminalData(_ data: Data) async {
        // Forward terminal input from viewer to pty
        guard let bridge = ptyBridge else { return }
        bridge.write(data)
    }

    // MARK: - PTY Read Loop

    private func ptyReadLoop(bridge: PTYBridge) async {
        let bufferSize = 16384
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while bridge.isAlive {
            let bytesRead = bridge.read(into: &buffer, maxLength: bufferSize)
            if bytesRead > 0 {
                let data = Data(buffer[0..<bytesRead])
                do {
                    try await webSocketTask?.send(.data(data))
                } catch {
                    print("[RelayConnector] Failed to send pty data: \(error)")
                    break
                }
            } else if bytesRead == 0 {
                // EOF — pty closed
                break
            } else {
                // Error
                if errno != EINTR {
                    break
                }
            }
        }

        print("[RelayConnector] PTY read loop ended")
        await detachCurrentSession()
    }

    // MARK: - Disconnect & Reconnect

    private func handleDisconnect(error: (any Error)?) async {
        state = .disconnected
        webSocketTask = nil

        // Clean up pty
        if let bridge = ptyBridge {
            bridge.terminate()
            ptyBridge = nil
        }

        // Try to reconnect if we have saved parameters
        if let relayURL = savedRelayURL, let token = savedToken {
            let shouldReconnect = reconnectAttempt < Self.maxReconnectAttempt
            if shouldReconnect {
                reconnectAttempt += 1
                let delay = reconnectDelay()
                print("[RelayConnector] Reconnecting in \(String(format: "%.1f", delay))s (attempt \(reconnectAttempt)/\(Self.maxReconnectAttempt))...")

                do {
                    try await Task.sleep(for: .seconds(delay))
                    try await establishConnection(relayURL: relayURL, token: token)
                    return
                } catch {
                    print("[RelayConnector] Reconnection failed: \(error.localizedDescription)")
                }
            }
        }

        // Signal runUntilDisconnected to return
        disconnectContinuation?.resume(returning: ())
        disconnectContinuation = nil
    }

    /// Exponential backoff with jitter.
    private func reconnectDelay() -> TimeInterval {
        let base = Self.baseReconnectDelay * pow(2.0, Double(reconnectAttempt - 1))
        let capped = min(base, Self.maxReconnectDelay)
        let jitter = Double.random(in: 0...(capped * 0.1))
        return capped + jitter
    }
}

// MARK: - Errors

enum RelayConnectorError: Error, LocalizedError {
    case invalidURL(String)
    case encodingFailed
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url): "Invalid relay URL: \(url)"
        case .encodingFailed: "Failed to encode control message"
        case .connectionFailed(let reason): "Connection failed: \(reason)"
        }
    }
}
