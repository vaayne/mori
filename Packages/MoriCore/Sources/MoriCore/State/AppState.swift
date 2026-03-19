import Foundation

@MainActor
@Observable
public final class AppState {
    public var projects: [Project] = []
    public var worktrees: [Worktree] = []
    public var runtimeWindows: [RuntimeWindow] = []
    public var runtimePanes: [RuntimePane] = []
    public var uiState: UIState = UIState()

    public init() {}

    // MARK: - Derived state

    public var selectedProject: Project? {
        guard let id = uiState.selectedProjectId else { return nil }
        return projects.first { $0.id == id }
    }

    public var selectedWorktree: Worktree? {
        guard let id = uiState.selectedWorktreeId else { return nil }
        return worktrees.first { $0.id == id }
    }

    public var selectedWindow: RuntimeWindow? {
        guard let id = uiState.selectedWindowId else { return nil }
        return runtimeWindows.first { $0.tmuxWindowId == id }
    }

    /// Worktrees for the currently selected project.
    public var worktreesForSelectedProject: [Worktree] {
        guard let projectId = uiState.selectedProjectId else { return [] }
        return worktrees.filter { $0.projectId == projectId }
    }

    /// Runtime windows for the currently selected worktree.
    public var windowsForSelectedWorktree: [RuntimeWindow] {
        guard let worktreeId = uiState.selectedWorktreeId else { return [] }
        return runtimeWindows
            .filter { $0.worktreeId == worktreeId }
            .sorted { $0.tmuxWindowIndex < $1.tmuxWindowIndex }
    }

    /// Runtime panes for a given window.
    public func panes(forWindow windowId: String) -> [RuntimePane] {
        runtimePanes.filter { $0.tmuxWindowId == windowId }
    }
}
