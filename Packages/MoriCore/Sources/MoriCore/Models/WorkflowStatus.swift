import Foundation

public enum WorkflowStatus: String, Codable, Sendable, CaseIterable {
    case todo
    case inProgress
    case needsReview
    case done
    case cancelled

    public var displayName: String {
        switch self {
        case .todo: "To Do"
        case .inProgress: "In Progress"
        case .needsReview: "Needs Review"
        case .done: "Done"
        case .cancelled: "Cancelled"
        }
    }

    public var iconName: String {
        switch self {
        case .todo: "circle"
        case .inProgress: "circle.dotted.circle"
        case .needsReview: "eye.circle"
        case .done: "checkmark.circle.fill"
        case .cancelled: "xmark.circle"
        }
    }

    public var sortOrder: Int {
        switch self {
        case .inProgress: 0
        case .needsReview: 1
        case .todo: 2
        case .done: 3
        case .cancelled: 4
        }
    }
}
