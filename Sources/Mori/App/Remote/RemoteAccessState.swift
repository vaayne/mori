import Foundation

/// Observable state for the Remote Access feature.
/// Drives the settings UI and status indicators.
@Observable
@MainActor
final class RemoteAccessState {

    // MARK: - Persisted Settings

    /// Relay WebSocket URL (e.g. "wss://mori-relay.fly.dev/ws").
    var relayURL: String {
        didSet { UserDefaults.standard.set(relayURL, forKey: Self.relayURLKey) }
    }

    // MARK: - Runtime State

    /// Whether remote access is currently enabled (connector running).
    var isEnabled: Bool = false

    /// Current connection status.
    var status: RemoteStatus = .disconnected

    /// The pairing token for the current session (generated on enable).
    var pairingToken: String?

    /// The pairing URI encoded in the QR code.
    var pairingURI: String?

    /// QR code image data (PNG) for the current pairing token.
    var qrCodePNGData: Data?

    /// Number of connected viewers.
    var viewerCount: Int = 0

    /// Last error message, if any.
    var lastError: String?

    // MARK: - Init

    init() {
        self.relayURL = UserDefaults.standard.string(forKey: Self.relayURLKey)
            ?? Self.defaultRelayURL
    }

    // MARK: - Constants

    static let relayURLKey = "MoriRemoteRelayURL"
    static let defaultRelayURL = "ws://localhost:19820/ws"
}

/// Status of the remote access connection.
enum RemoteStatus: Equatable, Sendable {
    case disconnected
    case connecting
    case waitingForViewer
    case viewerConnected
    case error(String)

    var displayText: String {
        switch self {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting..."
        case .waitingForViewer: "Waiting for viewer"
        case .viewerConnected: "Viewer connected"
        case .error(let msg): "Error: \(msg)"
        }
    }

    var isActive: Bool {
        switch self {
        case .connecting, .waitingForViewer, .viewerConnected: true
        default: false
        }
    }
}
