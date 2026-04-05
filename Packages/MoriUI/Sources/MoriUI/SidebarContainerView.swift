import SwiftUI
import MoriCore

/// Container view with a segmented control toggle (Tasks | Workspaces) at top,
/// plus an agent-mode toggle button. When agent mode is active, `AgentSidebarView`
/// replaces the content regardless of which base mode is selected.
public struct SidebarContainerView: View {
    private let sidebarMode: SidebarMode
    private let onToggleSidebarMode: (SidebarMode) -> Void

    // Shared data
    private let projects: [Project]
    private let selectedProjectId: UUID?
    private let worktrees: [Worktree]
    private let windows: [RuntimeWindow]
    private let selectedWorktreeId: UUID?
    private let selectedWindowId: String?

    // Shared callbacks
    private let onSelectProject: ((UUID) -> Void)?
    private let onSelectWorktree: (UUID) -> Void
    private let onSelectWindow: (String) -> Void
    private let onShowCreatePanel: (() -> Void)?
    private let onRemoveWorktree: ((UUID) -> Void)?
    private let onRemoveProject: ((UUID) -> Void)?
    private let onEditRemoteProject: ((UUID) -> Void)?
    private let onCloseWindow: ((String) -> Void)?
    private let onToggleCollapse: ((UUID) -> Void)?
    private let onAddProject: (() -> Void)?
    private let onOpenSettings: (() -> Void)?
    private let onOpenCommandPalette: (() -> Void)?
    private let onSetWorkflowStatus: ((UUID, WorkflowStatus) -> Void)?
    private let onRequestPaneOutput: ((String, @escaping (String?) -> Void) -> Void)?
    private let onSendKeys: ((String, String) -> Void)?
    private let onUpdateProject: ((Project) -> Void)?

    public init(
        sidebarMode: SidebarMode,
        onToggleSidebarMode: @escaping (SidebarMode) -> Void,
        projects: [Project] = [],
        selectedProjectId: UUID? = nil,
        worktrees: [Worktree],
        windows: [RuntimeWindow],
        selectedWorktreeId: UUID?,
        selectedWindowId: String?,
        onSelectProject: ((UUID) -> Void)? = nil,
        onSelectWorktree: @escaping (UUID) -> Void,
        onSelectWindow: @escaping (String) -> Void,
        onShowCreatePanel: (() -> Void)? = nil,
        onRemoveWorktree: ((UUID) -> Void)? = nil,
        onRemoveProject: ((UUID) -> Void)? = nil,
        onEditRemoteProject: ((UUID) -> Void)? = nil,
        onCloseWindow: ((String) -> Void)? = nil,
        onToggleCollapse: ((UUID) -> Void)? = nil,
        onAddProject: (() -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onOpenCommandPalette: (() -> Void)? = nil,
        onSetWorkflowStatus: ((UUID, WorkflowStatus) -> Void)? = nil,
        onRequestPaneOutput: ((String, @escaping (String?) -> Void) -> Void)? = nil,
        onSendKeys: ((String, String) -> Void)? = nil,
        onUpdateProject: ((Project) -> Void)? = nil
    ) {
        self.sidebarMode = sidebarMode
        self.onToggleSidebarMode = onToggleSidebarMode
        self.projects = projects
        self.selectedProjectId = selectedProjectId
        self.worktrees = worktrees
        self.windows = windows
        self.selectedWorktreeId = selectedWorktreeId
        self.selectedWindowId = selectedWindowId
        self.onSelectProject = onSelectProject
        self.onSelectWorktree = onSelectWorktree
        self.onSelectWindow = onSelectWindow
        self.onShowCreatePanel = onShowCreatePanel
        self.onRemoveWorktree = onRemoveWorktree
        self.onRemoveProject = onRemoveProject
        self.onEditRemoteProject = onEditRemoteProject
        self.onCloseWindow = onCloseWindow
        self.onToggleCollapse = onToggleCollapse
        self.onAddProject = onAddProject
        self.onOpenSettings = onOpenSettings
        self.onOpenCommandPalette = onOpenCommandPalette
        self.onSetWorkflowStatus = onSetWorkflowStatus
        self.onRequestPaneOutput = onRequestPaneOutput
        self.onSendKeys = onSendKeys
        self.onUpdateProject = onUpdateProject
    }

    /// Shared Cmd-hold shortcut hint monitor — one instance for the entire sidebar.
    @StateObject private var shortcutHintMonitor = ShortcutHintModifierMonitor()

    public var body: some View {
        VStack(spacing: 0) {
            headerRow

            // Content
            switch sidebarMode {
            case .agentTasks:
                AgentSidebarView(
                    projects: projects,
                    worktrees: worktrees,
                    windows: windows,
                    selectedWindowId: selectedWindowId,
                    shortcutHintsVisible: shortcutHintMonitor.areHintsVisible,
                    onSelectWindow: onSelectWindow,
                    onRequestPaneOutput: onRequestPaneOutput,
                    onSendKeys: onSendKeys,
                    onAddProject: onAddProject,
                    onOpenSettings: onOpenSettings,
                    onOpenCommandPalette: onOpenCommandPalette
                )
            case .tasks:
                TaskSidebarView(
                    projects: projects,
                    worktrees: worktrees,
                    windows: windows,
                    selectedWorktreeId: selectedWorktreeId,
                    selectedWindowId: selectedWindowId,
                    onSelectWorktree: onSelectWorktree,
                    onSelectWindow: onSelectWindow,
                    onCloseWindow: onCloseWindow,
                    onRemoveWorktree: onRemoveWorktree,
                    onSetWorkflowStatus: onSetWorkflowStatus,
                    onAddProject: onAddProject,
                    onOpenSettings: onOpenSettings,
                    onOpenCommandPalette: onOpenCommandPalette,
                    shortcutHintsVisible: shortcutHintMonitor.areHintsVisible,
                    onRequestPaneOutput: onRequestPaneOutput,
                    onSendKeys: onSendKeys
                )
            case .workspaces:
                WorktreeSidebarView(
                    projects: projects,
                    selectedProjectId: selectedProjectId,
                    worktrees: worktrees,
                    windows: windows,
                    selectedWorktreeId: selectedWorktreeId,
                    selectedWindowId: selectedWindowId,
                    shortcutHintsVisible: shortcutHintMonitor.areHintsVisible,
                    onSelectProject: onSelectProject,
                    onSelectWorktree: onSelectWorktree,
                    onSelectWindow: onSelectWindow,
                    onShowCreatePanel: onShowCreatePanel,
                    onRemoveWorktree: onRemoveWorktree,
                    onRemoveProject: onRemoveProject,
                    onEditRemoteProject: onEditRemoteProject,
                    onCloseWindow: onCloseWindow,
                    onToggleCollapse: onToggleCollapse,
                    onAddProject: onAddProject,
                    onOpenSettings: onOpenSettings,
                    onOpenCommandPalette: onOpenCommandPalette,
                    onSetWorkflowStatus: onSetWorkflowStatus,
                    onRequestPaneOutput: onRequestPaneOutput,
                    onSendKeys: onSendKeys,
                    onUpdateProject: onUpdateProject
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            shortcutHintMonitor.start()
        }
        .onDisappear {
            shortcutHintMonitor.stop()
        }
    }

    // MARK: - Header

    /// Three-segment picker: Workspaces | Tasks | Agents.
    private var headerRow: some View {
        Picker("", selection: Binding(
            get: { sidebarMode },
            set: { onToggleSidebarMode($0) }
        )) {
            Text(String.localized("Workspaces")).tag(SidebarMode.workspaces)
            Text(String.localized("Tasks")).tag(SidebarMode.tasks)
            Text(String.localized("Agents")).tag(SidebarMode.agentTasks)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, MoriTokens.Spacing.xl)
        .padding(.top, MoriTokens.Spacing.lg)
        .padding(.bottom, MoriTokens.Spacing.sm)
    }
}
