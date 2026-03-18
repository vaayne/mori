import AppKit
import SwiftUI
import MoriCore
import MoriUI

// MARK: - Project Rail Hosting

/// Wraps ProjectRailView in an NSHostingController, observing AppState.
@MainActor
final class ProjectRailHostingController: NSHostingController<ProjectRailContentView> {

    init(appState: AppState, onSelect: @escaping (UUID) -> Void) {
        let rootView = ProjectRailContentView(appState: appState, onSelect: onSelect)
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Bindable wrapper that reads AppState observables into ProjectRailView.
struct ProjectRailContentView: View {
    @Bindable var appState: AppState
    let onSelect: (UUID) -> Void

    var body: some View {
        ProjectRailView(
            projects: appState.projects,
            selectedProjectId: appState.uiState.selectedProjectId,
            onSelect: onSelect
        )
    }
}

// MARK: - Worktree Sidebar Hosting

/// Wraps WorktreeSidebarView in an NSHostingController, observing AppState.
@MainActor
final class WorktreeSidebarHostingController: NSHostingController<WorktreeSidebarContentView> {

    init(
        appState: AppState,
        onSelectWorktree: @escaping (UUID) -> Void,
        onSelectWindow: @escaping (String) -> Void,
        onCreateWorktree: ((String) -> Void)? = nil,
        onRemoveWorktree: ((UUID) -> Void)? = nil
    ) {
        let rootView = WorktreeSidebarContentView(
            appState: appState,
            onSelectWorktree: onSelectWorktree,
            onSelectWindow: onSelectWindow,
            onCreateWorktree: onCreateWorktree,
            onRemoveWorktree: onRemoveWorktree
        )
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Bindable wrapper that reads AppState observables into WorktreeSidebarView.
struct WorktreeSidebarContentView: View {
    @Bindable var appState: AppState
    let onSelectWorktree: (UUID) -> Void
    let onSelectWindow: (String) -> Void
    let onCreateWorktree: ((String) -> Void)?
    let onRemoveWorktree: ((UUID) -> Void)?

    var body: some View {
        WorktreeSidebarView(
            worktrees: appState.worktreesForSelectedProject,
            windows: appState.runtimeWindows,
            selectedWorktreeId: appState.uiState.selectedWorktreeId,
            selectedWindowId: appState.uiState.selectedWindowId,
            onSelectWorktree: onSelectWorktree,
            onSelectWindow: onSelectWindow,
            onCreateWorktree: onCreateWorktree,
            onRemoveWorktree: onRemoveWorktree
        )
    }
}
