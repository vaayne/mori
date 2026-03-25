import Foundation

/// Protocol version for handshake negotiation.
public let protocolVersion: UInt = 1

/// Control messages exchanged as JSON text WebSocket frames.
/// Terminal data is sent as binary WebSocket frames (no wrapping).
public enum ControlMessage: Sendable, Codable {
    case handshake(Handshake)
    case sessionList(SessionList)
    case attach(Attach)
    case detach(Detach)
    case resize(Resize)
    case modeChange(ModeChange)
    case heartbeat(Heartbeat)
    case error(ErrorMessage)

    // MARK: - Payload Types

    public struct Handshake: Sendable, Codable {
        public var version: UInt
        public var role: Role
        public var capabilities: [String]

        public init(version: UInt = protocolVersion, role: Role, capabilities: [String] = []) {
            self.version = version
            self.role = role
            self.capabilities = capabilities
        }
    }

    public struct SessionList: Sendable, Codable {
        public var sessions: [SessionInfo]

        public init(sessions: [SessionInfo]) {
            self.sessions = sessions
        }
    }

    public struct Attach: Sendable, Codable {
        public var sessionName: String
        public var mode: SessionMode

        public init(sessionName: String, mode: SessionMode = .readOnly) {
            self.sessionName = sessionName
            self.mode = mode
        }
    }

    public struct Detach: Sendable, Codable {
        public var reason: String?

        public init(reason: String? = nil) {
            self.reason = reason
        }
    }

    public struct Resize: Sendable, Codable {
        public var cols: UInt16
        public var rows: UInt16

        public init(cols: UInt16, rows: UInt16) {
            self.cols = cols
            self.rows = rows
        }
    }

    public struct ModeChange: Sendable, Codable {
        public var mode: SessionMode

        public init(mode: SessionMode) {
            self.mode = mode
        }
    }

    public struct Heartbeat: Sendable, Codable {
        public var timestamp: UInt64

        public init(timestamp: UInt64 = UInt64(Date().timeIntervalSince1970 * 1000)) {
            self.timestamp = timestamp
        }
    }

    public struct ErrorMessage: Sendable, Codable {
        public var code: ErrorCode
        public var message: String

        public init(code: ErrorCode, message: String) {
            self.code = code
            self.message = message
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type, payload
    }

    private var typeName: String {
        switch self {
        case .handshake: "handshake"
        case .sessionList: "session_list"
        case .attach: "attach"
        case .detach: "detach"
        case .resize: "resize"
        case .modeChange: "mode_change"
        case .heartbeat: "heartbeat"
        case .error: "error"
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(typeName, forKey: .type)
        switch self {
        case .handshake(let v): try container.encode(v, forKey: .payload)
        case .sessionList(let v): try container.encode(v, forKey: .payload)
        case .attach(let v): try container.encode(v, forKey: .payload)
        case .detach(let v): try container.encode(v, forKey: .payload)
        case .resize(let v): try container.encode(v, forKey: .payload)
        case .modeChange(let v): try container.encode(v, forKey: .payload)
        case .heartbeat(let v): try container.encode(v, forKey: .payload)
        case .error(let v): try container.encode(v, forKey: .payload)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "handshake": self = .handshake(try container.decode(Handshake.self, forKey: .payload))
        case "session_list": self = .sessionList(try container.decode(SessionList.self, forKey: .payload))
        case "attach": self = .attach(try container.decode(Attach.self, forKey: .payload))
        case "detach": self = .detach(try container.decode(Detach.self, forKey: .payload))
        case "resize": self = .resize(try container.decode(Resize.self, forKey: .payload))
        case "mode_change": self = .modeChange(try container.decode(ModeChange.self, forKey: .payload))
        case "heartbeat": self = .heartbeat(try container.decode(Heartbeat.self, forKey: .payload))
        case "error": self = .error(try container.decode(ErrorMessage.self, forKey: .payload))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown message type: \(type)")
        }
    }
}
