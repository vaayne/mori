import Foundation

/// Role in the relay connection.
public enum Role: String, Sendable, Codable {
    case host
    case viewer
}

/// Terminal session mode.
public enum SessionMode: String, Sendable, Codable {
    /// Read-only: tmux attach -r (ignore-size, no input forwarded)
    case readOnly = "read_only"
    /// Interactive: grouped tmux session (independent size, input forwarded)
    case interactive
}

/// Info about a tmux session available for remote access.
public struct SessionInfo: Sendable, Codable, Identifiable {
    public var id: String { name }
    public var name: String
    public var displayName: String
    public var windowCount: Int
    public var attached: Bool

    public init(name: String, displayName: String, windowCount: Int, attached: Bool) {
        self.name = name
        self.displayName = displayName
        self.windowCount = windowCount
        self.attached = attached
    }
}

/// Error codes for the protocol error message.
public enum ErrorCode: String, Sendable, Codable {
    case versionMismatch = "version_mismatch"
    case sessionNotFound = "session_not_found"
    case alreadyAttached = "already_attached"
    case tokenExpired = "token_expired"
    case tokenInvalid = "token_invalid"
    case rateLimited = "rate_limited"
    case internalError = "internal_error"
}
