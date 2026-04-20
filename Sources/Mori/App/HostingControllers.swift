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
    private let chromePaletteStore: MoriChromePaletteStore

    init(
        appState: AppState,
        onSelectProject: @escaping (UUID) -> Void,
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
        onRequestPaneOutput: ((String, @escaping (String?) -> Void) -> Void)? = nil,
        onSendKeys: ((String, String) -> Void)? = nil,
        onUpdateProject: ((Project) -> Void)? = nil,
        onReorderProjects: (([UUID]) -> Void)? = nil,
        chromePalette: MoriChromePalette = .fallback
    ) {
        self.appState = appState
        self.chromePaletteStore = MoriChromePaletteStore(palette: chromePalette)
        let rootView = SidebarContentView(
            appState: appState,
            chromePaletteStore: chromePaletteStore,
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
    func updateAppearance(themeInfo: GhosttyThemeInfo, chromePalette: MoriChromePalette) {
        chromePaletteStore.palette = chromePalette
        view.appearance = NSAppearance(named: themeInfo.isDark ? .darkAqua : .aqua)
        view.layer?.backgroundColor = themeInfo.usesTransparentWindowBackground
            ? NSColor.clear.cgColor
            : chromePalette.sidebarBackground.nsColor.cgColor
        view.needsDisplay = true
    }
}

/// Bindable wrapper that reads AppState observables into SidebarContainerView.
struct SidebarContentView: View {
    @Bindable var appState: AppState
    let chromePaletteStore: MoriChromePaletteStore
    let onSelectProject: (UUID) -> Void
    let onSelectWorktree: (UUID) -> Void
    let onSelectWindow: (String) -> Void
    let onShowCreatePanel: (() -> Void)?
    let onRemoveWorktree: ((UUID) -> Void)?
    let onRemoveProject: ((UUID) -> Void)?
    let onEditRemoteProject: ((UUID) -> Void)?
    let onCloseWindow: ((String) -> Void)?
    let onToggleCollapse: ((UUID) -> Void)?
    let onAddProject: (() -> Void)?
    let onOpenSettings: (() -> Void)?
    let onOpenCommandPalette: (() -> Void)?
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
            selectedWorktreeId: appState.uiState.selectedWorktreeId,
            selectedWindowId: appState.uiState.selectedWindowId,
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
            onRequestPaneOutput: onRequestPaneOutput,
            onSendKeys: onSendKeys,
            onUpdateProject: onUpdateProject,
            onReorderProjects: onReorderProjects
        )
        .environmentObject(chromePaletteStore)
    }
}
