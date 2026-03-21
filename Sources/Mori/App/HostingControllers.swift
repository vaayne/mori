import AppKit
import SwiftUI
import MoriCore
import MoriTerminal
import MoriUI

// MARK: - Sidebar Hosting (unified: project picker + worktrees + actions)

@MainActor
final class SidebarHostingController: NSHostingController<SidebarContentView> {

    private let appState: AppState

    init(
        appState: AppState,
        appearanceStore: SidebarAppearanceStore,
        onSelectProject: @escaping (UUID) -> Void,
        onSelectWorktree: @escaping (UUID) -> Void,
        onSelectWindow: @escaping (String) -> Void,
        onCreateWorktree: ((String) -> Void)? = nil,
        onRemoveWorktree: ((UUID) -> Void)? = nil,
        onRemoveProject: ((UUID) -> Void)? = nil,
        onCloseWindow: ((String) -> Void)? = nil,
        onToggleCollapse: ((UUID) -> Void)? = nil,
        onAddProject: (() -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onOpenCommandPalette: (() -> Void)? = nil
    ) {
        self.appState = appState
        let rootView = SidebarContentView(
            appState: appState,
            appearanceStore: appearanceStore,
            onSelectProject: onSelectProject,
            onSelectWorktree: onSelectWorktree,
            onSelectWindow: onSelectWindow,
            onCreateWorktree: onCreateWorktree,
            onRemoveWorktree: onRemoveWorktree,
            onRemoveProject: onRemoveProject,
            onCloseWindow: onCloseWindow,
            onToggleCollapse: onToggleCollapse,
            onAddProject: onAddProject,
            onOpenSettings: onOpenSettings,
            onOpenCommandPalette: onOpenCommandPalette
        )
        super.init(rootView: rootView)
        sizingOptions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateAppearance(themeInfo: GhosttyThemeInfo) {
        view.appearance = NSAppearance(named: themeInfo.isDark ? .darkAqua : .aqua)
        view.wantsLayer = true
        view.layer?.backgroundColor = themeInfo.background.cgColor
    }
}

struct SidebarContentView: View {
    @Bindable var appState: AppState
    @Bindable var appearanceStore: SidebarAppearanceStore
    let onSelectProject: (UUID) -> Void
    let onSelectWorktree: (UUID) -> Void
    let onSelectWindow: (String) -> Void
    let onCreateWorktree: ((String) -> Void)?
    let onRemoveWorktree: ((UUID) -> Void)?
    let onRemoveProject: ((UUID) -> Void)?
    let onCloseWindow: ((String) -> Void)?
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
            onSelectProject: onSelectProject,
            onSelectWorktree: onSelectWorktree,
            onSelectWindow: onSelectWindow,
            onCreateWorktree: onCreateWorktree,
            onRemoveWorktree: onRemoveWorktree,
            onRemoveProject: onRemoveProject,
            onCloseWindow: onCloseWindow,
            onToggleCollapse: onToggleCollapse,
            onAddProject: onAddProject,
            onOpenSettings: onOpenSettings,
            onOpenCommandPalette: onOpenCommandPalette
        )
        .environment(\.sidebarAppearance, appearanceStore.appearance)
    }
}
