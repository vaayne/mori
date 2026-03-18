import Foundation

public enum AlertState: String, Codable, Sendable, Comparable {
    case none
    case info
    case dirty
    case unread
    case waiting
    case warning
    case error

    // MARK: - Comparable (priority ordering)

    /// Priority value for ordering. Higher means more urgent.
    /// error > waiting > warning > unread > dirty > info > none
    private var priority: Int {
        switch self {
        case .none: return 0
        case .info: return 1
        case .dirty: return 2
        case .unread: return 3
        case .warning: return 4
        case .waiting: return 5
        case .error: return 6
        }
    }

    public static func < (lhs: AlertState, rhs: AlertState) -> Bool {
        lhs.priority < rhs.priority
    }
}
