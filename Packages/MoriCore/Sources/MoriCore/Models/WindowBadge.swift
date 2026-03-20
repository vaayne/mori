import Foundation

public enum WindowBadge: String, Codable, Sendable {
    case idle
    case unread
    case error
    case running
    case waiting
    case longRunning
    case agentDone
}
