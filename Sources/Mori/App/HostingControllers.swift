import AppKit
import SwiftUI
import MoriCore
import MoriUI

// MARK: - Sidebar Hosting (unified: project picker + worktrees + actions)

/// Wraps WorktreeSidebarView in an NSHostingController, observing AppState.
@MainActor
final class SidebarHostingController: NSHostingController<SidebarContentView> {

    private let appState: AppState

    init(
        appState: AppState,
        onSelectProject: @escaping (UUID) -> Void,
        onSelectWorktree: @escaping (UUID) -> Void,
        onSelectWindow: @escaping (String) -> Void,
        onCreateWorktree: ((String) -> Void)? = nil,
        onRemoveWorktree: ((UUID) -> Void)? = nil,
        onRemoveProject: ((UUID) -> Void)? = nil,
        onToggleCollapse: ((UUID) -> Void)? = nil,
        onAddProject: (() -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onOpenCommandPalette: (() -> Void)? = nil
    ) {
        self.appState = appState
        let rootView = SidebarContentView(
            appState: appState,
            onSelectProject: onSelectProject,
            onSelectWorktree: onSelectWorktree,
            onSelectWindow: onSelectWindow,
            onCreateWorktree: onCreateWorktree,
            onRemoveWorktree: onRemoveWorktree,
            onRemoveProject: onRemoveProject,
            onToggleCollapse: onToggleCollapse,
            onAddProject: onAddProject,
            onOpenSettings: onOpenSettings,
            onOpenCommandPalette: onOpenCommandPalette
        )
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Sync the hosting controller's view appearance with the terminal theme.
    func updateAppearance(settings: TerminalSettings) {
        view.appearance = NSAppearance(named: settings.theme.isDark ? .darkAqua : .aqua)
    }
}

/// Bindable wrapper that reads AppState observables into WorktreeSidebarView.
struct SidebarContentView: View {
    @Bindable var appState: AppState
    let onSelectProject: (UUID) -> Void
    let onSelectWorktree: (UUID) -> Void
    let onSelectWindow: (String) -> Void
    let onCreateWorktree: ((String) -> Void)?
    let onRemoveWorktree: ((UUID) -> Void)?
    let onRemoveProject: ((UUID) -> Void)?
    let onToggleCollapse: ((UUID) -> Void)?
    let onAddProject: (() -> Void)?
    let onOpenSettings: (() -> Void)?
    let onOpenCommandPalette: (() -> Void)?

    var body: some View {
        WorktreeSidebarView(
            projects: appState.projects,
            selectedProjectId: appState.uiState.selectedProjectId,
            worktrees: appState.worktrees,
            windows: appState.runtimeWindows,
            selectedWorktreeId: appState.uiState.selectedWorktreeId,
            selectedWindowId: appState.uiState.selectedWindowId,
            theme: appState.terminalSettings.theme,
            onSelectProject: onSelectProject,
            onSelectWorktree: onSelectWorktree,
            onSelectWindow: onSelectWindow,
            onCreateWorktree: onCreateWorktree,
            onRemoveWorktree: onRemoveWorktree,
            onRemoveProject: onRemoveProject,
            onToggleCollapse: onToggleCollapse,
            onAddProject: onAddProject,
            onOpenSettings: onOpenSettings,
            onOpenCommandPalette: onOpenCommandPalette
        )
    }
}
