import Foundation
import MoriRemoteProtocol

/// Navigation state for the app flow:
/// QR scanner -> session list -> terminal
enum AppScreen: Sendable, Equatable {
    case scanner
    case sessionList
    case terminal(sessionName: String)
}

/// Central view model coordinating the relay client, navigation flow,
/// and connection state for the entire iOS app.
@Observable
@MainActor
final class AppViewModel {

    // MARK: - Navigation

    var currentScreen: AppScreen = .scanner
    var connectionStatus: ConnectionStatus = .disconnected

    // MARK: - Session List

    var sessions: [SessionInfo] = []
    var currentMode: SessionMode = .readOnly

    // MARK: - Connection info (persisted across launches)

    var relayHost: String? {
        get { UserDefaults.standard.string(forKey: "relayHost") }
        set { UserDefaults.standard.set(newValue, forKey: "relayHost") }
    }

    // MARK: - Relay Client

    let relayClient = RelayClient()

    // MARK: - Init

    init() {
        Task { await setupCallbacks() }
    }

    // MARK: - Setup

    private func setupCallbacks() async {
        await relayClient.setOnStateChange { [weak self] state in
            Task { @MainActor in
                self?.handleStateChange(state)
            }
        }

        await relayClient.setOnControlMessage { [weak self] message in
            Task { @MainActor in
                self?.handleControlMessage(message)
            }
        }
    }

    // MARK: - QR Pairing

    /// Called when a QR code is scanned or URL is manually entered.
    /// Format: `mori-relay://<host>/<token>`
    func handleScannedURL(_ urlString: String) {
        guard let parsed = parseRelayURL(urlString) else {
            NSLog("[AppViewModel] Invalid relay URL: \(urlString)")
            return
        }

        relayHost = parsed.host

        Task {
            do {
                try await relayClient.connect(
                    relayURL: parsed.wsURL,
                    token: parsed.token
                )
            } catch {
                NSLog("[AppViewModel] Connection failed: \(error)")
                connectionStatus = .disconnected
            }
        }
    }

    /// Parse `mori-relay://<host>/<token>` into components.
    private func parseRelayURL(_ urlString: String) -> (host: String, token: String, wsURL: String)? {
        // Accept both mori-relay:// and wss:// formats
        let normalized: String
        if urlString.hasPrefix("mori-relay://") {
            normalized = urlString.replacingOccurrences(of: "mori-relay://", with: "")
        } else if urlString.hasPrefix("wss://") || urlString.hasPrefix("ws://") {
            // Direct WebSocket URL — extract host and token from path
            guard let url = URL(string: urlString),
                  let host = url.host,
                  !url.pathComponents.isEmpty else { return nil }
            let token = url.pathComponents.last ?? ""
            let port = url.port.map { ":\($0)" } ?? ""
            let scheme = urlString.hasPrefix("wss://") ? "wss" : "ws"
            return (host: "\(host)\(port)", token: token, wsURL: "\(scheme)://\(host)\(port)/ws")
        } else {
            return nil
        }

        // Format: <host>/<token> or <host>:<port>/<token>
        let parts = normalized.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return nil }

        let host = String(parts[0])
        let token = String(parts[1])

        // Use ws:// for localhost/LAN, wss:// for public hosts
        let isLocal = host.hasPrefix("localhost") || host.hasPrefix("127.0.0.1")
            || host.hasPrefix("192.168.") || host.hasPrefix("10.")
        let scheme = isLocal ? "ws" : "wss"
        let wsURL = "\(scheme)://\(host)/ws"

        return (host: host, token: token, wsURL: wsURL)
    }

    // MARK: - Session Actions

    func requestSessionList() {
        Task {
            let message = ControlMessage.sessionList(
                ControlMessage.SessionList(sessions: [])
            )
            try? await relayClient.sendControlMessage(message)
        }
    }

    func attachSession(_ session: SessionInfo) {
        Task {
            let message = ControlMessage.attach(
                ControlMessage.Attach(sessionName: session.name, mode: currentMode)
            )
            try? await relayClient.sendControlMessage(message)
            currentScreen = .terminal(sessionName: session.name)
        }
    }

    func detachSession() {
        Task {
            try? await relayClient.sendControlMessage(
                ControlMessage.detach(ControlMessage.Detach(reason: "user detached"))
            )
            currentScreen = .sessionList
        }
    }

    // MARK: - Mode Toggle

    func toggleMode() {
        currentMode = (currentMode == .readOnly) ? .interactive : .readOnly

        Task {
            try? await relayClient.sendControlMessage(
                ControlMessage.modeChange(ControlMessage.ModeChange(mode: currentMode))
            )
        }
    }

    // MARK: - Resize

    func sendResize(cols: UInt16, rows: UInt16) {
        Task {
            try? await relayClient.sendControlMessage(
                ControlMessage.resize(ControlMessage.Resize(cols: cols, rows: rows))
            )
        }
    }

    // MARK: - Device Revocation

    func forgetDevice() {
        Task {
            await relayClient.disconnect(reason: "device forgotten")
            await relayClient.invalidateSession()
            relayHost = nil
            sessions = []
            currentScreen = .scanner
            connectionStatus = .disconnected
        }
    }

    // MARK: - Auto-reconnect on return

    func attemptReconnect() {
        guard relayHost != nil else { return }
        Task {
            let hasSession = await relayClient.hasStoredSession
            if hasSession {
                let success = await relayClient.reconnect()
                if !success {
                    // Session expired, go back to scanner
                    currentScreen = .scanner
                }
            } else {
                currentScreen = .scanner
            }
        }
    }

    func disconnectForBackground() async {
        let state = await relayClient.state
        if case .disconnected = state { return }
        await relayClient.disconnect(reason: "app backgrounded")
    }

    // MARK: - Callbacks

    private func handleStateChange(_ state: ConnectionState) {
        switch state {
        case .disconnected:
            connectionStatus = .disconnected
        case .pairing:
            connectionStatus = .connecting
        case .connected:
            connectionStatus = .connected
            // Connected — request session list
            if case .scanner = currentScreen {
                currentScreen = .sessionList
            }
            requestSessionList()
        case .attached:
            connectionStatus = .connected
        case .detached:
            connectionStatus = .connected
            if case .terminal = currentScreen {
                currentScreen = .sessionList
            }
        }
    }

    private func handleControlMessage(_ message: ControlMessage) {
        switch message {
        case .sessionList(let list):
            sessions = list.sessions
        case .error(let err):
            NSLog("[AppViewModel] Error: \(err.code.rawValue) - \(err.message)")
            if err.code == .tokenExpired || err.code == .tokenInvalid {
                currentScreen = .scanner
                connectionStatus = .disconnected
            }
        default:
            break
        }
    }
}

// MARK: - Connection Status

enum ConnectionStatus: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting
}
