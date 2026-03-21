import SwiftUI
import MoriCore

/// Container view with a segmented control toggle (Tasks | Workspaces) at top.
/// Conditionally renders `TaskSidebarView` or `WorktreeSidebarView`, passing through all callbacks.
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
    private let onCloseWindow: ((String) -> Void)?
    private let onToggleCollapse: ((UUID) -> Void)?
    private let onAddProject: (() -> Void)?
    private let onOpenSettings: (() -> Void)?
    private let onOpenCommandPalette: (() -> Void)?
    private let onSetWorkflowStatus: ((UUID, WorkflowStatus) -> Void)?

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
        onCloseWindow: ((String) -> Void)? = nil,
        onToggleCollapse: ((UUID) -> Void)? = nil,
        onAddProject: (() -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onOpenCommandPalette: (() -> Void)? = nil,
        onSetWorkflowStatus: ((UUID, WorkflowStatus) -> Void)? = nil
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
        self.onCloseWindow = onCloseWindow
        self.onToggleCollapse = onToggleCollapse
        self.onAddProject = onAddProject
        self.onOpenSettings = onOpenSettings
        self.onOpenCommandPalette = onOpenCommandPalette
        self.onSetWorkflowStatus = onSetWorkflowStatus
    }

    @State private var selectedMode: SidebarMode = .workspaces

    public var body: some View {
        VStack(spacing: 0) {
            // Segmented control toggle
            Picker("", selection: Binding(
                get: { sidebarMode },
                set: { onToggleSidebarMode($0) }
            )) {
                Text(String.localized("Tasks")).tag(SidebarMode.tasks)
                Text(String.localized("Workspaces")).tag(SidebarMode.workspaces)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, MoriTokens.Spacing.xl)
            .padding(.top, MoriTokens.Spacing.lg)
            .padding(.bottom, MoriTokens.Spacing.sm)

            // Conditional view
            switch sidebarMode {
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
                    onSetWorkflowStatus: onSetWorkflowStatus,
                    onAddProject: onAddProject,
                    onOpenSettings: onOpenSettings,
                    onOpenCommandPalette: onOpenCommandPalette
                )
            case .workspaces:
                WorktreeSidebarView(
                    projects: projects,
                    selectedProjectId: selectedProjectId,
                    worktrees: worktrees,
                    windows: windows,
                    selectedWorktreeId: selectedWorktreeId,
                    selectedWindowId: selectedWindowId,
                    onSelectProject: onSelectProject,
                    onSelectWorktree: onSelectWorktree,
                    onSelectWindow: onSelectWindow,
                    onShowCreatePanel: onShowCreatePanel,
                    onRemoveWorktree: onRemoveWorktree,
                    onRemoveProject: onRemoveProject,
                    onCloseWindow: onCloseWindow,
                    onToggleCollapse: onToggleCollapse,
                    onAddProject: onAddProject,
                    onOpenSettings: onOpenSettings,
                    onOpenCommandPalette: onOpenCommandPalette,
                    onSetWorkflowStatus: onSetWorkflowStatus
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
