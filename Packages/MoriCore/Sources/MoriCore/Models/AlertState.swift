import Foundation

public enum AlertState: String, Codable, Sendable {
    case none
    case info
    case warning
    case error
}
