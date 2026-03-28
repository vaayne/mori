import Foundation
import MoriCore

/// Represents an item in the command palette search results.
enum CommandPaletteItem: Sendable {
    case project(id: UUID, name: String)
    case worktree(id: UUID, projectId: UUID, name: String, branch: String?)
    case window(id: String, worktreeId: UUID, title: String, tag: WindowTag?)
    case action(id: String, title: String, subtitle: String?)

    var title: String {
        switch self {
        case .project(_, let name):
            return name
        case .worktree(_, _, let name, _):
            return name
        case .window(_, _, let title, _):
            return title
        case .action(_, let title, _):
            return title
        }
    }

    var subtitle: String? {
        switch self {
        case .project:
            return .localized("Project")
        case .worktree(_, _, _, let branch):
            return branch.map { .localized("Branch: \($0)") } ?? .localized("Worktree")
        case .window(_, _, _, let tag):
            if let tag {
                return .localized("Window (\(tag.rawValue))")
            }
            return .localized("Window")
        case .action(_, _, let subtitle):
            return subtitle
        }
    }

    var shortcutHint: String? {
        switch self {
        case .action(let id, _, _):
            switch id {
            case "action.refresh": return "⌘R"
            case "action.open-project": return "⌘O"
            default: return nil
            }
        default:
            return nil
        }
    }

    var iconName: String? {
        switch self {
        case .project:
            return "folder.fill"
        case .worktree:
            return "arrow.triangle.branch"
        case .window(_, _, _, let tag):
            return tag?.symbolName ?? "terminal"
        case .action(let id, _, _):
            switch id {
            case "action.create-worktree":
                return "plus.circle"
            case "action.refresh":
                return "arrow.clockwise"
            case "action.open-project":
                return "folder.badge.plus"
            case "action.remote-connect":
                return "network"
            case "action.check-for-updates":
                return "arrow.triangle.2.circlepath"
            default:
                return "command"
            }
        }
    }
}
