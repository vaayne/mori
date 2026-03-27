import AppKit
import SwiftUI
import MoriCore
import MoriTerminal
import MoriUI

// MARK: - Sidebar Hosting (unified: project picker + worktrees + actions)

/// Wraps SidebarContainerView in an NSHostingController, observing AppState.
@MainActor
final class SidebarHostingController: NSHostingController<SidebarContentView> {

    private let appState: AppState

    init(
        appState: AppState,
        onSelectProject: @escaping (UUID) -> Void,
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
        onToggleSidebarMode: ((SidebarMode) -> Void)? = nil,
        onSetWorkflowStatus: ((UUID, WorkflowStatus) -> Void)? = nil
    ) {
        self.appState = appState
        let rootView = SidebarContentView(
            appState: appState,
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
            onToggleSidebarMode: onToggleSidebarMode,
            onSetWorkflowStatus: onSetWorkflowStatus
        )
        super.init(rootView: rootView)
        // Prevent SwiftUI's layout from dictating the view size.
        // Without this, the hosting controller sets a preferred content size
        // that locks the split view sidebar to a fixed width.
        sizingOptions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Sync the hosting controller's view appearance with the ghostty theme.
    func updateAppearance(themeInfo: GhosttyThemeInfo) {
        view.appearance = NSAppearance(named: themeInfo.isDark ? .darkAqua : .aqua)
        view.wantsLayer = true
        view.layer?.backgroundColor = themeInfo.background.cgColor
    }
}

/// Bindable wrapper that reads AppState observables into SidebarContainerView.
struct SidebarContentView: View {
    @Bindable var appState: AppState
    let onSelectProject: (UUID) -> Void
    let onSelectWorktree: (UUID) -> Void
    let onSelectWindow: (String) -> Void
    let onShowCreatePanel: (() -> Void)?
    let onRemoveWorktree: ((UUID) -> Void)?
    let onRemoveProject: ((UUID) -> Void)?
    let onCloseWindow: ((String) -> Void)?
    let onToggleCollapse: ((UUID) -> Void)?
    let onAddProject: (() -> Void)?
    let onOpenSettings: (() -> Void)?
    let onOpenCommandPalette: (() -> Void)?
    let onToggleSidebarMode: ((SidebarMode) -> Void)?
    let onSetWorkflowStatus: ((UUID, WorkflowStatus) -> Void)?

    var body: some View {
        SidebarContainerView(
            sidebarMode: appState.uiState.sidebarMode,
            onToggleSidebarMode: { mode in
                onToggleSidebarMode?(mode)
            },
            projects: appState.projects,
            selectedProjectId: appState.uiState.selectedProjectId,
            worktrees: appState.worktrees,
            windows: appState.runtimeWindows,
            selectedWorktreeId: appState.uiState.selectedWorktreeId,
            selectedWindowId: appState.uiState.selectedWindowId,
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
