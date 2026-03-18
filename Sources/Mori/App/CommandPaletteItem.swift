import Foundation

/// Represents an item in the command palette search results.
enum CommandPaletteItem: Sendable {
    case project(id: UUID, name: String)
    case worktree(id: UUID, projectId: UUID, name: String, branch: String?)
    case window(id: String, worktreeId: UUID, title: String)
    case action(id: String, title: String, subtitle: String?)

    var title: String {
        switch self {
        case .project(_, let name):
            return name
        case .worktree(_, _, let name, _):
            return name
        case .window(_, _, let title):
            return title
        case .action(_, let title, _):
            return title
        }
    }

    var subtitle: String? {
        switch self {
        case .project:
            return "Project"
        case .worktree(_, _, _, let branch):
            return branch.map { "Branch: \($0)" } ?? "Worktree"
        case .window:
            return "Window"
        case .action(_, _, let subtitle):
            return subtitle
        }
    }

    var iconName: String? {
        switch self {
        case .project:
            return "folder.fill"
        case .worktree:
            return "arrow.triangle.branch"
        case .window:
            return "terminal"
        case .action(let id, _, _):
            switch id {
            case "action.create-worktree":
                return "plus.circle"
            case "action.refresh":
                return "arrow.clockwise"
            case "action.open-project":
                return "folder.badge.plus"
            default:
                return "command"
            }
        }
    }
}
