import Foundation

/// Errors that can occur during SSH operations.
public enum SSHError: Error, Sendable, LocalizedError {
    case connectionFailed(String)
    case authenticationFailed
    case timeout
    case channelError(String)
    case disconnected

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let reason):
            return "SSH connection failed: \(reason)"
        case .authenticationFailed:
            return "SSH authentication failed"
        case .timeout:
            return "SSH connection timed out"
        case .channelError(let reason):
            return "SSH channel error: \(reason)"
        case .disconnected:
            return "SSH disconnected"
        }
    }
}
