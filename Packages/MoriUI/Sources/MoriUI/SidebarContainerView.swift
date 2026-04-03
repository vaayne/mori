import SwiftUI
import MoriCore

/// Container view with a segmented control toggle (Tasks | Workspaces) at top.
/// Conditionally renders `TaskSidebarView`, `AgentSidebarView`, or `WorktreeSidebarView`,
/// passing through all callbacks.
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
        onSendKeys: ((String, String) -> Void)? = nil
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
    }

    /// Whether the current mode is tasks-like (tasks or agentTasks).
    private var isTasksMode: Bool {
        sidebarMode == .tasks || sidebarMode == .agentTasks
    }

    /// Count of active agent windows (running, waiting, or error).
    private var activeAgentCount: Int {
        windows.filter {
            $0.agentState == .running ||
            $0.agentState == .waitingForInput ||
            $0.agentState == .error
        }.count
    }

    /// Whether any agent needs attention (waiting for input or error).
    private var hasAgentAttention: Bool {
        windows.contains { $0.agentState == .waitingForInput || $0.agentState == .error }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Segmented control toggle — map .agentTasks → .tasks for display
            Picker("", selection: Binding(
                get: { isTasksMode ? SidebarMode.tasks : sidebarMode },
                set: { onToggleSidebarMode($0) }
            )) {
                Text(String.localized("Tasks")).tag(SidebarMode.tasks)
                Text(String.localized("Workspaces")).tag(SidebarMode.workspaces)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, MoriTokens.Spacing.xl)
            .padding(.top, MoriTokens.Spacing.lg)
            .padding(.bottom, MoriTokens.Spacing.sm)

            // Agent mode toggle pill — visible in tasks mode
            if isTasksMode {
                agentModePill
            }

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
                    onRemoveWorktree: onRemoveWorktree,
                    onSetWorkflowStatus: onSetWorkflowStatus,
                    onAddProject: onAddProject,
                    onOpenSettings: onOpenSettings,
                    onOpenCommandPalette: onOpenCommandPalette,
                    onRequestPaneOutput: onRequestPaneOutput,
                    onSendKeys: onSendKeys
                )
            case .agentTasks:
                AgentSidebarView(
                    projects: projects,
                    worktrees: worktrees,
                    windows: windows,
                    selectedWindowId: selectedWindowId,
                    onSelectWindow: onSelectWindow,
                    onRequestPaneOutput: onRequestPaneOutput,
                    onSendKeys: onSendKeys,
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
                    onEditRemoteProject: onEditRemoteProject,
                    onCloseWindow: onCloseWindow,
                    onToggleCollapse: onToggleCollapse,
                    onAddProject: onAddProject,
                    onOpenSettings: onOpenSettings,
                    onOpenCommandPalette: onOpenCommandPalette,
                    onSetWorkflowStatus: onSetWorkflowStatus,
                    onRequestPaneOutput: onRequestPaneOutput,
                    onSendKeys: onSendKeys
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Agent Mode Pill

    private var agentModePill: some View {
        let isActive = sidebarMode == .agentTasks
        let pillColor: Color = isActive
            ? (hasAgentAttention ? MoriTokens.Color.attention : MoriTokens.Color.success)
            : MoriTokens.Color.muted

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                onToggleSidebarMode(isActive ? .tasks : .agentTasks)
            }
        } label: {
            HStack(spacing: MoriTokens.Spacing.sm) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(pillColor)

                Text(String.localized("Agents only"))
                    .font(MoriTokens.Font.caption)
                    .foregroundStyle(pillColor)

                if activeAgentCount > 0 {
                    Text("\(activeAgentCount)")
                        .font(MoriTokens.Font.badgeCount)
                        .foregroundStyle(isActive ? pillColor : MoriTokens.Color.muted)
                        .padding(.horizontal, MoriTokens.Spacing.sm)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(pillColor.opacity(isActive ? 0.15 : 0.08))
                        )
                }
            }
            .padding(.horizontal, MoriTokens.Spacing.lg)
            .padding(.vertical, MoriTokens.Spacing.sm)
            .background(
                Capsule()
                    .fill(isActive ? pillColor.opacity(0.1) : Color.clear)
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                isActive ? pillColor.opacity(0.35) : MoriTokens.Color.muted.opacity(0.2),
                                lineWidth: 1
                            )
                    )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, MoriTokens.Spacing.xl)
        .padding(.bottom, MoriTokens.Spacing.sm)
    }
}
