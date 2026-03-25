import Foundation
import AppKit
import CoreImage
import MoriRemoteProtocol
import MoriTmux

/// Manages the relay WebSocket connection for remote terminal access.
/// Bridges local tmux sessions to a remote viewer via the Mori relay protocol.
actor RemoteAccessManager {

    // MARK: - State

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var ptyBridge: RemotePTYBridge?
    private var connectionState: ConnectionState = .disconnected
    private var currentSessionName: String?
    private var currentMode: SessionMode = .readOnly
    private var sessionID: String?

    /// Token used for pairing.
    private var token: String?

    /// Reconnection state.
    private var reconnectAttempt: Int = 0
    private static let maxReconnectAttempt = 10
    private static let baseReconnectDelay: TimeInterval = 1.0
    private static let maxReconnectDelay: TimeInterval = 60.0

    /// Saved parameters for reconnection.
    private var savedRelayURL: String?

    /// Connection task for cancellation.
    private var connectionTask: Task<Void, Never>?

    /// Grouped session manager for interactive mode cleanup.
    private let groupedSessionManager = RemoteGroupedSessionManager()

    /// Callback to push state updates to the main actor.
    private let onStateChange: @Sendable (RemoteStatus) -> Void

    // MARK: - Init

    init(onStateChange: @escaping @Sendable (RemoteStatus) -> Void) {
        self.onStateChange = onStateChange
    }

    // MARK: - Public API

    /// Start remote access: connect to relay with the given pairing token.
    func start(relayURL: String, token: String) async throws {
        self.token = token
        self.savedRelayURL = relayURL
        try await establishConnection(relayURL: relayURL, token: token)
    }

    /// Stop remote access: disconnect and clean up.
    func stop() async {
        connectionTask?.cancel()
        connectionTask = nil

        await detachCurrentSession()
        await groupedSessionManager.cleanupAll()

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil

        connectionState = .disconnected
        token = nil
        savedRelayURL = nil
        sessionID = nil
        reconnectAttempt = 0

        onStateChange(.disconnected)
    }

    /// Get the current token.
    func currentToken() -> String? {
        token
    }

    // MARK: - Connection

    private func establishConnection(relayURL: String, token: String) async throws {
        guard var components = URLComponents(string: relayURL) else {
            throw RemoteAccessError.invalidURL(relayURL)
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "token", value: token))
        queryItems.append(URLQueryItem(name: "role", value: Role.host.rawValue))
        if let sessionID {
            queryItems.append(URLQueryItem(name: "session_id", value: sessionID))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw RemoteAccessError.invalidURL(relayURL)
        }

        onStateChange(.connecting)

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        task.resume()

        self.urlSession = session
        self.webSocketTask = task

        // Send handshake
        let handshake = ControlMessage.handshake(
            ControlMessage.Handshake(role: .host)
        )
        try await sendControlMessage(handshake)

        connectionState = .connected
        reconnectAttempt = 0
        onStateChange(.waitingForViewer)

        // Start receive loop
        connectionTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    // MARK: - WebSocket Receive Loop

    private func receiveLoop() async {
        guard let task = webSocketTask else { return }

        while !Task.isCancelled {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await task.receive()
            } catch {
                if !Task.isCancelled {
                    await handleDisconnect(error: error)
                }
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
                do {
                    try await attachSession(name: attach.sessionName, mode: attach.mode)
                    onStateChange(.viewerConnected)
                } catch {
                    let errMsg = ControlMessage.error(ControlMessage.ErrorMessage(
                        code: .sessionNotFound,
                        message: "Failed to attach session '\(attach.sessionName)': \(error.localizedDescription)"
                    ))
                    try? await sendControlMessage(errMsg)
                }

            case .detach:
                await detachCurrentSession()
                onStateChange(.waitingForViewer)

            case .resize(let resize):
                ptyBridge?.resize(cols: resize.cols, rows: resize.rows)

            case .modeChange(let modeChange):
                if let sessionName = currentSessionName {
                    await detachCurrentSession()
                    try? await attachSession(name: sessionName, mode: modeChange.mode)
                }

            case .sessionList:
                let sessions = await listLocalSessions()
                let response = ControlMessage.sessionList(
                    ControlMessage.SessionList(sessions: sessions)
                )
                try? await sendControlMessage(response)

            case .heartbeat(let heartbeat):
                let pong = ControlMessage.heartbeat(
                    ControlMessage.Heartbeat(timestamp: heartbeat.timestamp)
                )
                try? await sendControlMessage(pong)

            case .handshake(let hs):
                if let sid = hs.capabilities.first(where: { $0.hasPrefix("session_id:") }) {
                    self.sessionID = String(sid.dropFirst("session_id:".count))
                }

            case .error(let err):
                onStateChange(.error("\(err.code.rawValue): \(err.message)"))
            }
        } catch {
            // Failed to decode — ignore malformed messages
        }
    }

    private func handleTerminalData(_ data: Data) async {
        guard let bridge = ptyBridge else { return }
        bridge.write(data)
    }

    // MARK: - Session Management

    private func attachSession(name: String, mode: SessionMode) async throws {
        if ptyBridge != nil {
            await detachCurrentSession()
        }

        currentSessionName = name
        currentMode = mode

        let tmuxCommand: [String]
        switch mode {
        case .readOnly:
            tmuxCommand = ["tmux", "attach-session", "-r", "-t", name]
        case .interactive:
            let groupedName = try await groupedSessionManager.createGroupedSession(target: name)
            tmuxCommand = ["tmux", "attach-session", "-t", groupedName]
        }

        let bridge = try RemotePTYBridge(command: tmuxCommand)
        self.ptyBridge = bridge

        Task { [weak self] in
            await self?.ptyReadLoop(bridge: bridge)
        }
    }

    private func detachCurrentSession() async {
        if let bridge = ptyBridge {
            bridge.terminate()
            ptyBridge = nil
        }

        if currentMode == .interactive, let sessionName = currentSessionName {
            await groupedSessionManager.cleanupGroupedSessions(for: sessionName)
        }

        currentSessionName = nil
    }

    // MARK: - PTY Read Loop

    private func ptyReadLoop(bridge: RemotePTYBridge) async {
        let bufferSize = 16384
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while bridge.isAlive {
            let bytesRead = bridge.read(into: &buffer, maxLength: bufferSize)
            if bytesRead > 0 {
                let data = Data(buffer[0..<bytesRead])
                do {
                    try await webSocketTask?.send(.data(data))
                } catch {
                    break
                }
            } else if bytesRead == 0 {
                break
            } else {
                if errno != EINTR { break }
            }
        }

        await detachCurrentSession()
    }

    // MARK: - Disconnect & Reconnect

    private func handleDisconnect(error: (any Error)?) async {
        connectionState = .disconnected
        webSocketTask = nil

        if let bridge = ptyBridge {
            bridge.terminate()
            ptyBridge = nil
        }

        if let relayURL = savedRelayURL, let token = self.token {
            if reconnectAttempt < Self.maxReconnectAttempt {
                reconnectAttempt += 1
                let delay = reconnectDelay()
                onStateChange(.connecting)

                do {
                    try await Task.sleep(for: .seconds(delay))
                    try await establishConnection(relayURL: relayURL, token: token)
                    return
                } catch {
                    // Reconnection failed — fall through to disconnect
                }
            }
        }

        onStateChange(.disconnected)
    }

    private func reconnectDelay() -> TimeInterval {
        let base = Self.baseReconnectDelay * pow(2.0, Double(reconnectAttempt - 1))
        let capped = min(base, Self.maxReconnectDelay)
        let jitter = Double.random(in: 0...(capped * 0.1))
        return capped + jitter
    }

    // MARK: - Helpers

    private func sendControlMessage(_ message: ControlMessage) async throws {
        let data = try encodeMessage(message)
        guard let text = String(data: data, encoding: .utf8) else {
            throw RemoteAccessError.encodingFailed
        }
        try await webSocketTask?.send(.string(text))
    }

    private func listLocalSessions() async -> [SessionInfo] {
        let runner = TmuxCommandRunner()
        do {
            let output = try await runner.run(
                "list-sessions", "-F", TmuxParser.sessionFormat
            )
            if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return []
            }
            let sessions = TmuxParser.parseSessions(output)
            return sessions.map { session in
                let displayName: String
                if let parsed = SessionNaming.parse(session.name) {
                    displayName = "\(parsed.projectShortName) / \(parsed.branchSlug)"
                } else {
                    displayName = session.name
                }
                return SessionInfo(
                    name: session.name,
                    displayName: displayName,
                    windowCount: session.windowCount,
                    attached: session.isAttached
                )
            }
        } catch {
            return []
        }
    }
}

// MARK: - QR Code Generation

extension RemoteAccessManager {

    /// Generate a pairing URI from the relay URL and token.
    /// Format: `mori-relay://<host>:<port>/<token>`
    /// The iOS app reconstructs the WebSocket URL from host:port.
    static func pairingURI(relayURL: String, token: String) -> String {
        guard let components = URLComponents(string: relayURL),
              let hostPart = components.host else {
            return "mori-relay://localhost/\(token)"
        }
        let portPart = components.port.map { ":\($0)" } ?? ""
        return "mori-relay://\(hostPart)\(portPart)/\(token)"
    }

    /// Generate a QR code PNG from the given content string.
    static func generateQRCodePNG(from content: String, size: CGFloat = 256) -> Data? {
        guard let data = content.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }

        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else { return nil }

        let scaleX = size / ciImage.extent.width
        let scaleY = size / ciImage.extent.height
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return nil
        }

        let nsImage = NSBitmapImageRep(cgImage: cgImage)
        return nsImage.representation(using: .png, properties: [:])
    }
}

// MARK: - Errors

enum RemoteAccessError: Error, LocalizedError {
    case invalidURL(String)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url): "Invalid relay URL: \(url)"
        case .encodingFailed: "Failed to encode control message"
        }
    }
}
