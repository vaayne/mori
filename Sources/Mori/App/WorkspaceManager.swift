import Foundation
import MoriCore
import MoriPersistence
import MoriTmux

/// Coordinates project/worktree/window selection flow across AppState,
/// persistence, and tmux backend. Lives in the app target to avoid
/// circular SPM dependencies between MoriCore, MoriPersistence, and MoriTmux.
@MainActor
final class WorkspaceManager {

    let appState: AppState
    let projectRepo: ProjectRepository
    let worktreeRepo: WorktreeRepository
    let uiStateRepo: UIStateRepository
    let tmuxBackend: TmuxBackend

    /// Callback invoked when the terminal should switch to a different session.
    /// Parameters: (sessionName, workingDirectory)
    var onTerminalSwitch: ((String, String) -> Void)?

    init(
        appState: AppState,
        projectRepo: ProjectRepository,
        worktreeRepo: WorktreeRepository,
        uiStateRepo: UIStateRepository,
        tmuxBackend: TmuxBackend
    ) {
        self.appState = appState
        self.projectRepo = projectRepo
        self.worktreeRepo = worktreeRepo
        self.uiStateRepo = uiStateRepo
        self.tmuxBackend = tmuxBackend
    }

    // MARK: - Load All State

    /// Load all projects and worktrees from the database into AppState.
    func loadAll() throws {
        appState.projects = try projectRepo.fetchAll()
        var allWorktrees: [Worktree] = []
        for project in appState.projects {
            let wts = try worktreeRepo.fetchAll(forProject: project.id)
            allWorktrees.append(contentsOf: wts)
        }
        appState.worktrees = allWorktrees
        appState.uiState = try uiStateRepo.fetch()
    }

    // MARK: - Select Project

    func selectProject(_ projectId: UUID) {
        appState.uiState.selectedProjectId = projectId
        appState.uiState.selectedWorktreeId = nil
        appState.uiState.selectedWindowId = nil

        // Auto-select first worktree if available
        let worktrees = appState.worktreesForSelectedProject
        if let first = worktrees.first {
            selectWorktree(first.id)
        }

        saveUIState()
    }

    // MARK: - Select Worktree

    func selectWorktree(_ worktreeId: UUID) {
        appState.uiState.selectedWorktreeId = worktreeId
        appState.uiState.selectedWindowId = nil

        guard let worktree = appState.worktrees.first(where: { $0.id == worktreeId }) else { return }

        // Ensure tmux session exists, then switch terminal
        Task {
            await ensureTmuxSession(for: worktree)
            await refreshRuntimeState()

            // Notify terminal to switch to this worktree's session
            if let sessionName = worktree.tmuxSessionName {
                onTerminalSwitch?(sessionName, worktree.path)
            }
        }

        saveUIState()
    }

    // MARK: - Select Window

    func selectWindow(_ windowId: String) {
        appState.uiState.selectedWindowId = windowId

        // Find the window's worktree session to switch tmux window
        if let window = appState.runtimeWindows.first(where: { $0.tmuxWindowId == windowId }),
           let worktree = appState.worktrees.first(where: { $0.id == window.worktreeId }),
           let sessionName = worktree.tmuxSessionName {
            Task {
                try? await tmuxBackend.selectWindow(sessionId: sessionName, windowId: windowId)
            }
            // Ensure terminal is attached to the right session and focused
            onTerminalSwitch?(sessionName, worktree.path)
        }

        saveUIState()
    }

    // MARK: - Add Project

    /// Add a new project from a directory path. Creates Project, default Worktree,
    /// and tmux session. Returns the new project.
    @discardableResult
    func addProject(path: String) throws -> Project {
        let name = (path as NSString).lastPathComponent

        // Create project
        let project = Project(
            name: name,
            repoRootPath: path,
            gitCommonDir: path,
            lastActiveAt: Date()
        )
        try projectRepo.save(project)

        // Create default worktree
        let sessionName = SessionNaming.sessionName(project: name, worktree: "main")
        let worktree = Worktree(
            projectId: project.id,
            name: "main",
            path: path,
            branch: "main",
            isMainWorktree: true,
            tmuxSessionName: sessionName,
            status: .active
        )
        try worktreeRepo.save(worktree)

        // Create tmux session
        Task {
            _ = try? await tmuxBackend.createSession(name: sessionName, cwd: path)
            await tmuxBackend.refreshNow()
        }

        // Refresh state
        try loadAll()

        // Select the new project
        selectProject(project.id)

        return project
    }

    // MARK: - Tmux Integration

    /// Ensure a tmux session exists for the given worktree, creating one if needed.
    private func ensureTmuxSession(for worktree: Worktree) async {
        guard let sessionName = worktree.tmuxSessionName else { return }

        let sessions = (try? await tmuxBackend.scanAll()) ?? []
        let exists = sessions.contains { $0.name == sessionName }

        if !exists {
            _ = try? await tmuxBackend.createSession(name: sessionName, cwd: worktree.path)
        }
    }

    /// Refresh runtime windows/panes from tmux into AppState.
    func refreshRuntimeState() async {
        guard let sessions = try? await tmuxBackend.scanAll() else { return }

        var runtimeWindows: [RuntimeWindow] = []

        for session in sessions where session.isMoriSession {
            // Find matching worktree
            guard let worktree = appState.worktrees.first(where: {
                $0.tmuxSessionName == session.name
            }) else { continue }

            for tmuxWindow in session.windows {
                let rw = RuntimeWindow(
                    tmuxWindowId: tmuxWindow.windowId,
                    worktreeId: worktree.id,
                    tmuxWindowIndex: tmuxWindow.windowIndex,
                    title: tmuxWindow.name,
                    paneCount: tmuxWindow.panes.count
                )
                runtimeWindows.append(rw)
            }
        }

        appState.runtimeWindows = runtimeWindows
    }

    // MARK: - Persistence

    private func saveUIState() {
        try? uiStateRepo.save(appState.uiState)
    }
}
