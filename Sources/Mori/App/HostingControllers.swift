import AppKit
import SwiftUI
import MoriCore
import MoriTerminal
import MoriUI

// MARK: - Sidebar Hosting (unified: project picker + worktrees + actions)

@MainActor
@Observable
final class SidebarLayoutState {
    var isCollapsed = false
}

/// Wraps SidebarContainerView in an NSHostingController, observing AppState.
@MainActor
final class SidebarHostingController: NSHostingController<SidebarContentView> {

    private let appState: AppState
    private let layoutState = SidebarLayoutState()

    init(
        appState: AppState,
        onSelectProject: @escaping (UUID) -> Void,
        onSelectWorktree: @escaping (UUID) -> Void,
        onSelectWindow: @escaping (String) -> Void,
        onSelectPane: ((String) -> Void)? = nil,
        onShowCreatePanel: (() -> Void)? = nil,
        onRemoveWorktree: ((UUID) -> Void)? = nil,
        onRemoveProject: ((UUID) -> Void)? = nil,
        onEditRemoteProject: ((UUID) -> Void)? = nil,
        onCloseWindow: ((String) -> Void)? = nil,
        onToggleCollapse: ((UUID) -> Void)? = nil,
        onAddProject: (() -> Void)? = nil,
        onRequestPaneOutput: ((String, @escaping (String?) -> Void) -> Void)? = nil,
        onSendKeys: ((String, String) -> Void)? = nil,
        onUpdateProject: ((Project) -> Void)? = nil,
        onReorderProjects: (([UUID]) -> Void)? = nil
    ) {
        self.appState = appState
        let rootView = SidebarContentView(
            appState: appState,
            layoutState: layoutState,
            onSelectProject: onSelectProject,
            onSelectWorktree: onSelectWorktree,
            onSelectWindow: onSelectWindow,
            onSelectPane: onSelectPane,
            onShowCreatePanel: onShowCreatePanel,
            onRemoveWorktree: onRemoveWorktree,
            onRemoveProject: onRemoveProject,
            onEditRemoteProject: onEditRemoteProject,
            onCloseWindow: onCloseWindow,
            onToggleCollapse: onToggleCollapse,
            onAddProject: onAddProject,
            onRequestPaneOutput: onRequestPaneOutput,
            onSendKeys: onSendKeys,
            onUpdateProject: onUpdateProject,
            onReorderProjects: onReorderProjects
        )
        super.init(rootView: rootView)
        // Prevent SwiftUI's layout from dictating the view size.
        // Without this, the hosting controller sets a preferred content size
        // that locks the split view sidebar to a fixed width.
        sizingOptions = []
        // Ensure the view is layer-backed so the theme background color shows through.
        view.wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Sync the hosting controller's view appearance with the ghostty theme.
    func updateAppearance(themeInfo: GhosttyThemeInfo) {
        view.appearance = NSAppearance(named: themeInfo.isDark ? .darkAqua : .aqua)
        view.layer?.backgroundColor = themeInfo.effectiveBackground.cgColor
        // Force SwiftUI to re-render with the updated appearance context.
        view.needsDisplay = true
    }

    func setSidebarCollapsed(_ isCollapsed: Bool) {
        layoutState.isCollapsed = isCollapsed
    }
}

/// Bindable wrapper that reads AppState observables into SidebarContainerView.
struct SidebarContentView: View {
    @Bindable var appState: AppState
    @Bindable var layoutState: SidebarLayoutState
    let onSelectProject: (UUID) -> Void
    let onSelectWorktree: (UUID) -> Void
    let onSelectWindow: (String) -> Void
    let onSelectPane: ((String) -> Void)?
    let onShowCreatePanel: (() -> Void)?
    let onRemoveWorktree: ((UUID) -> Void)?
    let onRemoveProject: ((UUID) -> Void)?
    let onEditRemoteProject: ((UUID) -> Void)?
    let onCloseWindow: ((String) -> Void)?
    let onToggleCollapse: ((UUID) -> Void)?
    let onAddProject: (() -> Void)?
    let onRequestPaneOutput: ((String, @escaping (String?) -> Void) -> Void)?
    let onSendKeys: ((String, String) -> Void)?
    let onUpdateProject: ((Project) -> Void)?
    let onReorderProjects: (([UUID]) -> Void)?

    var body: some View {
        SidebarContainerView(
            projects: appState.projects,
            selectedProjectId: appState.uiState.selectedProjectId,
            worktrees: appState.worktrees,
            windows: appState.runtimeWindows,
            panes: appState.runtimePanes,
            selectedWorktreeId: appState.uiState.selectedWorktreeId,
            selectedWindowId: appState.uiState.selectedWindowId,
            onSelectProject: onSelectProject,
            onSelectWorktree: onSelectWorktree,
            onSelectWindow: onSelectWindow,
            onSelectPane: onSelectPane,
            onShowCreatePanel: onShowCreatePanel,
            onRemoveWorktree: onRemoveWorktree,
            onRemoveProject: onRemoveProject,
            onEditRemoteProject: onEditRemoteProject,
            onCloseWindow: onCloseWindow,
            onToggleCollapse: onToggleCollapse,
            onAddProject: onAddProject,
            onRequestPaneOutput: onRequestPaneOutput,
            onSendKeys: onSendKeys,
            onUpdateProject: onUpdateProject,
            onReorderProjects: onReorderProjects,
            isSidebarCollapsed: layoutState.isCollapsed
        )
    }
}
