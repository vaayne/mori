import Foundation

public enum SidebarMode: String, Codable, Sendable {
    case workspaces
    case tasks
    case agents

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "workspaces":
            self = .workspaces
        case "tasks":
            self = .tasks
        case "agents":
            self = .agents
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
