import Foundation

public enum WindowBadge: String, Codable, Sendable {
    case none
    case unread
    case error
    case running
    case waiting
}
