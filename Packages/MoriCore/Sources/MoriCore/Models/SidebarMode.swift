import Foundation

public enum SidebarMode: String, Codable, Sendable {
    case workspaces
    case tasks

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "workspaces":
            self = .workspaces
        case "tasks":
            self = .tasks
        case "agents":
            // Backward compat: fold agents into tasks
            self = .tasks
        case "worktrees", "search":
            self = .workspaces
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown SidebarMode value: \(rawValue)"
            )
        }
    }
}
