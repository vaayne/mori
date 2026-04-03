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

    /// Whether agent mode is active.
    private var isAgentMode: Bool { sidebarMode == .agentTasks }

    /// The base mode for the picker (strips agentTasks → last non-agent mode).
    /// Tracks which picker segment to highlight when not in agent mode.
    @State private var lastBaseMode: SidebarMode = .tasks

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
            headerRow

            // Content
            switch sidebarMode {
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
                    onSendKeys: onSendKeys,
                    onUpdateProject: onUpdateProject
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: sidebarMode) { _, newValue in
            if newValue != .agentTasks {
                lastBaseMode = newValue
            }
        }
        .onAppear {
            if sidebarMode != .agentTasks {
                lastBaseMode = sidebarMode
            }
        }
    }

    // MARK: - Header

    /// Picker + agent toggle in a single row.
    private var headerRow: some View {
        HStack(spacing: MoriTokens.Spacing.md) {
            // Segmented control — deselects both segments when in agent mode
            Picker("", selection: Binding(
                get: { isAgentMode ? nil : sidebarMode },
                set: { newValue in
                    if let mode = newValue {
                        onToggleSidebarMode(mode)
                    }
                }
            )) {
                Text(String.localized("Tasks")).tag(Optional(SidebarMode.tasks))
                Text(String.localized("Workspaces")).tag(Optional(SidebarMode.workspaces))
            }
            .pickerStyle(.segmented)

            // Agent toggle button
            agentToggleButton
        }
        .padding(.horizontal, MoriTokens.Spacing.xl)
        .padding(.top, MoriTokens.Spacing.lg)
        .padding(.bottom, MoriTokens.Spacing.sm)
    }

    // MARK: - Agent Toggle Button

    private var agentToggleButton: some View {
        let badgeColor: Color = hasAgentAttention
            ? MoriTokens.Color.attention
            : (activeAgentCount > 0 ? MoriTokens.Color.success : MoriTokens.Color.muted)

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isAgentMode {
                    // Return to last base mode
                    onToggleSidebarMode(lastBaseMode)
                } else {
                    onToggleSidebarMode(.agentTasks)
                }
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: isAgentMode ? "bolt.fill" : "bolt")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isAgentMode ? badgeColor : MoriTokens.Color.muted)
                    .frame(width: 26, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: MoriTokens.Radius.small)
                            .fill(isAgentMode ? badgeColor.opacity(0.12) : Color.clear)
                    )

                // Live count badge
                if activeAgentCount > 0 {
                    Text("\(activeAgentCount)")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(
                            Capsule()
                                .fill(badgeColor)
                        )
                        .offset(x: 5, y: -5)
                }
            }
        }
        .buttonStyle(.plain)
        .help(isAgentMode
            ? String.localized("Exit agent mode")
            : String.localized("Show agents only"))
        .accessibilityLabel(String.localized("Agent mode"))
    }
}
