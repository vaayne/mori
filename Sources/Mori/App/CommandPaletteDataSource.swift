import Foundation
import MoriCore

/// Collects all searchable items from AppState and scores them against a query.
@MainActor
final class CommandPaletteDataSource {

    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    /// All available items from current AppState + static actions.
    func allItems() -> [CommandPaletteItem] {
        var items: [CommandPaletteItem] = []

        // Projects
        for project in appState.projects {
            items.append(.project(id: project.id, name: project.name))
        }

        // Worktrees for the selected project
        for worktree in appState.worktreesForSelectedProject where worktree.status == .active {
            items.append(.worktree(
                id: worktree.id,
                projectId: worktree.projectId,
                name: worktree.name,
                branch: worktree.branch
            ))
        }

        // Windows for the selected worktree
        for window in appState.windowsForSelectedWorktree {
            items.append(.window(
                id: window.tmuxWindowId,
                worktreeId: window.worktreeId,
                title: window.title,
                tag: window.tag
            ))
        }

        // Static actions
        items.append(.action(
            id: "action.create-worktree",
            title: .localized("Create Worktree"),
            subtitle: .localized("Create a new git worktree and tmux session")
        ))
        items.append(.action(
            id: "action.refresh",
            title: .localized("Refresh"),
            subtitle: .localized("Trigger a tmux and git status poll")
        ))
        items.append(.action(
            id: "action.open-project",
            title: .localized("Open Project"),
            subtitle: .localized("Add a project folder to Mori")
        ))
        items.append(.action(
            id: "action.remote-connect",
            title: "Remote: Connect to Host...",
            subtitle: "Add a remote SSH project"
        ))
        items.append(.action(
            id: "action.check-for-updates",
            title: .localized("Check for Updates"),
            subtitle: .localized("Check for available Mori updates")
        ))

        // Agent windows — searchable by agent name
        for window in appState.runtimeWindows where window.detectedAgent != nil {
            let worktree = appState.worktrees.first { $0.id == window.worktreeId }
            let project = worktree.flatMap { wt in appState.projects.first { $0.id == wt.projectId } }
            let context = [project?.name, worktree?.name].compactMap { $0 }.joined(separator: "/")
            items.append(.agent(
                windowId: window.tmuxWindowId,
                agentName: window.detectedAgent ?? window.title,
                context: context,
                state: window.agentState
            ))
        }

        // "Set Worktree Status" actions — only when a worktree is selected
        if let selectedWorktree = appState.selectedWorktree {
            for status in WorkflowStatus.allCases {
                let isCurrent = selectedWorktree.workflowStatus == status
                let subtitle: String = isCurrent
                    ? String.localized("Current status for \(selectedWorktree.name)")
                    : String.localized("Set \(selectedWorktree.name) to \(status.displayName)")
                items.append(.action(
                    id: "action.status-\(status.rawValue)",
                    title: .localized("Status: \(status.displayName)"),
                    subtitle: subtitle
                ))
            }
        }

        // "Set Worktree Status" actions — only when a worktree is selected
        if let selectedWorktree = appState.selectedWorktree {
            for status in WorkflowStatus.allCases {
                let isCurrent = selectedWorktree.workflowStatus == status
                let subtitle: String = isCurrent
                    ? String.localized("Current status for \(selectedWorktree.name)")
                    : String.localized("Set \(selectedWorktree.name) to \(status.displayName)")
                items.append(.action(
                    id: "action.status-\(status.rawValue)",
                    title: .localized("Status: \(status.displayName)"),
                    subtitle: subtitle
                ))
            }
        }

        return items
    }

    /// Score all items against a query and return sorted results (highest score first).
    /// Items with zero score are excluded.
    /// Supports `tag:<tagname>` prefix to filter windows by semantic tag.
    /// Supports `agent:` prefix to filter agent windows.
    func search(query: String) -> [CommandPaletteItem] {
        let items = allItems()

        if query.isEmpty {
            return items
        }

        // Handle "agent:" prefix filtering
        if query.lowercased().hasPrefix("agent:") {
            let agentQuery = String(query.dropFirst(6)).trimmingCharacters(in: .whitespaces).lowercased()
            return items.filter { item in
                if case .agent(_, let name, _, _) = item {
                    return agentQuery.isEmpty || name.lowercased().contains(agentQuery)
                }
                return false
            }
        }

        // Handle "tag:" prefix filtering
        if query.lowercased().hasPrefix("tag:") {
            let tagQuery = String(query.dropFirst(4)).trimmingCharacters(in: .whitespaces).lowercased()
            if tagQuery.isEmpty {
                // Show all tagged windows
                return items.filter { item in
                    if case .window(_, _, _, let tag) = item { return tag != nil }
                    return false
                }
            }
            return items.filter { item in
                if case .window(_, _, _, let tag) = item {
                    return tag?.rawValue.lowercased().hasPrefix(tagQuery) == true
                }
                return false
            }
        }

        let scored = items.compactMap { item -> (CommandPaletteItem, Int)? in
            // Score against title and subtitle
            let titleScore = FuzzyMatcher.score(query: query, candidate: item.title)
            let subtitleScore = item.subtitle.map { FuzzyMatcher.score(query: query, candidate: $0) } ?? 0
            let maxScore = max(titleScore, subtitleScore)
            guard maxScore > 0 else { return nil }
            return (item, maxScore)
        }

        return scored
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }
}
