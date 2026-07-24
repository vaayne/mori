import SwiftUI
import MoriCore

/// Container view for the unified sidebar.
/// Renders a single combined navigation surface for projects, worktrees, and windows.
public struct SidebarContainerView: View {

    // Shared data
    private let projects: [Project]
    private let selectedProjectId: UUID?
    private let worktrees: [Worktree]
    private let windows: [RuntimeWindow]
    private let panes: [RuntimePane]
    private let selectedWorktreeId: UUID?
    private let selectedWindowId: String?

    // Shared callbacks
    private let onSelectProject: ((UUID) -> Void)?
    private let onSelectWorktree: (UUID) -> Void
    private let onSelectWindow: (String) -> Void
    private let onSelectPane: ((String) -> Void)?
    private let onShowCreatePanel: (() -> Void)?
    private let onRemoveWorktree: ((UUID) -> Void)?
    private let onRemoveProject: ((UUID) -> Void)?
    private let onImportWorktrees: ((UUID) -> Void)?
    private let onEditRemoteProject: ((UUID) -> Void)?
    private let onCloseWindow: ((String) -> Void)?
    private let onToggleCollapse: ((UUID) -> Void)?
    private let onAddProject: (() -> Void)?
    private let onShowAgentDashboard: (() -> Void)?
    private let onOpenSettings: (() -> Void)?
    private let onRequestPaneOutput: ((String, @escaping (String?) -> Void) -> Void)?
    private let onSendKeys: ((String, String) -> Void)?
    private let onUpdateProject: ((Project) -> Void)?
    private let onReorderProjects: (([UUID]) -> Void)?
    private let pullRequests: [UUID: PullRequestInfo]

    public init(
        projects: [Project] = [],
        selectedProjectId: UUID? = nil,
        worktrees: [Worktree],
        windows: [RuntimeWindow],
        panes: [RuntimePane] = [],
        selectedWorktreeId: UUID?,
        selectedWindowId: String?,
        onSelectProject: ((UUID) -> Void)? = nil,
        onSelectWorktree: @escaping (UUID) -> Void,
        onSelectWindow: @escaping (String) -> Void,
        onSelectPane: ((String) -> Void)? = nil,
        onShowCreatePanel: (() -> Void)? = nil,
        onRemoveWorktree: ((UUID) -> Void)? = nil,
        onRemoveProject: ((UUID) -> Void)? = nil,
        onImportWorktrees: ((UUID) -> Void)? = nil,
        onEditRemoteProject: ((UUID) -> Void)? = nil,
        onCloseWindow: ((String) -> Void)? = nil,
        onToggleCollapse: ((UUID) -> Void)? = nil,
        onAddProject: (() -> Void)? = nil,
        onShowAgentDashboard: (() -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onRequestPaneOutput: ((String, @escaping (String?) -> Void) -> Void)? = nil,
        onSendKeys: ((String, String) -> Void)? = nil,
        onUpdateProject: ((Project) -> Void)? = nil,
        onReorderProjects: (([UUID]) -> Void)? = nil,
        pullRequests: [UUID: PullRequestInfo] = [:]
    ) {
        self.projects = projects
        self.selectedProjectId = selectedProjectId
        self.worktrees = worktrees
        self.windows = windows
        self.panes = panes
        self.selectedWorktreeId = selectedWorktreeId
        self.selectedWindowId = selectedWindowId
        self.onSelectProject = onSelectProject
        self.onSelectWorktree = onSelectWorktree
        self.onSelectWindow = onSelectWindow
        self.onSelectPane = onSelectPane
        self.onShowCreatePanel = onShowCreatePanel
        self.onRemoveWorktree = onRemoveWorktree
        self.onRemoveProject = onRemoveProject
        self.onImportWorktrees = onImportWorktrees
        self.onEditRemoteProject = onEditRemoteProject
        self.onCloseWindow = onCloseWindow
        self.onToggleCollapse = onToggleCollapse
        self.onAddProject = onAddProject
        self.onShowAgentDashboard = onShowAgentDashboard
        self.onOpenSettings = onOpenSettings
        self.onRequestPaneOutput = onRequestPaneOutput
        self.onSendKeys = onSendKeys
        self.onUpdateProject = onUpdateProject
        self.onReorderProjects = onReorderProjects
        self.pullRequests = pullRequests
    }

    /// Shared Cmd-hold shortcut hint monitor — one instance for the entire sidebar.
    @StateObject private var shortcutHintMonitor = ShortcutHintModifierMonitor()

    public var body: some View {
        WorktreeSidebarView(
            projects: projects,
            selectedProjectId: selectedProjectId,
            worktrees: worktrees,
            windows: windows,
            panes: panes,
            selectedWorktreeId: selectedWorktreeId,
            selectedWindowId: selectedWindowId,
            shortcutHintsVisible: shortcutHintMonitor.areHintsVisible,
            onSelectProject: onSelectProject,
            onSelectWorktree: onSelectWorktree,
            onSelectWindow: onSelectWindow,
            onSelectPane: onSelectPane,
            onShowCreatePanel: onShowCreatePanel,
            onRemoveWorktree: onRemoveWorktree,
            onRemoveProject: onRemoveProject,
            onImportWorktrees: onImportWorktrees,
            onEditRemoteProject: onEditRemoteProject,
            onCloseWindow: onCloseWindow,
            onToggleCollapse: onToggleCollapse,
            onAddProject: onAddProject,
            onShowAgentDashboard: onShowAgentDashboard,
            onOpenSettings: onOpenSettings,
            onRequestPaneOutput: onRequestPaneOutput,
            onSendKeys: onSendKeys,
            onUpdateProject: onUpdateProject,
            onReorderProjects: onReorderProjects,
            pullRequests: pullRequests
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            shortcutHintMonitor.start()
        }
        .onDisappear {
            shortcutHintMonitor.stop()
        }
    }
}
