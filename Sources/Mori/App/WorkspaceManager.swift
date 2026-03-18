import Foundation
import MoriCore
import MoriGit
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
    let gitBackend: GitBackend

    /// Callback invoked when the terminal should switch to a different session.
    /// Parameters: (sessionName, workingDirectory)
    var onTerminalSwitch: ((String, String) -> Void)?

    init(
        appState: AppState,
        projectRepo: ProjectRepository,
        worktreeRepo: WorktreeRepository,
        uiStateRepo: UIStateRepository,
        tmuxBackend: TmuxBackend,
        gitBackend: GitBackend = GitBackend()
    ) {
        self.appState = appState
        self.projectRepo = projectRepo
        self.worktreeRepo = worktreeRepo
        self.uiStateRepo = uiStateRepo
        self.tmuxBackend = tmuxBackend
        self.gitBackend = gitBackend
    }

    /// Whether tmux is available on this system.
    /// Set during loadAll() and used by AppDelegate to show alerts.
    private(set) var isTmuxAvailable: Bool = true

    // MARK: - Load All State

    /// Load all projects and worktrees from the database into AppState.
    /// Also validates project paths and marks unavailable ones.
    func loadAll() throws {
        appState.projects = try projectRepo.fetchAll()
        var allWorktrees: [Worktree] = []
        for project in appState.projects {
            let wts = try worktreeRepo.fetchAll(forProject: project.id)
            allWorktrees.append(contentsOf: wts)
        }
        appState.worktrees = allWorktrees
        appState.uiState = try uiStateRepo.fetch()

        // Validate project paths — mark unavailable if path no longer exists
        validateProjectPaths()
    }

    /// Check each worktree path and mark as unavailable if the directory is gone.
    private func validateProjectPaths() {
        let fm = FileManager.default
        for i in appState.worktrees.indices {
            var isDir: ObjCBool = false
            let exists = fm.fileExists(atPath: appState.worktrees[i].path, isDirectory: &isDir)
            if !exists || !isDir.boolValue {
                appState.worktrees[i].status = .unavailable
                // Persist the status change
                try? worktreeRepo.save(appState.worktrees[i])
            } else if appState.worktrees[i].status == .unavailable {
                // Path is back — restore to active
                appState.worktrees[i].status = .active
                try? worktreeRepo.save(appState.worktrees[i])
            }
        }
    }

    /// Check tmux availability. Returns true if tmux is found.
    func checkTmuxAvailability() async -> Bool {
        let available = await tmuxBackend.isAvailable()
        isTmuxAvailable = available
        return available
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
    /// Validates that the path is a git repo and resolves gitCommonDir.
    @discardableResult
    func addProject(path: String) async throws -> Project {
        let name = (path as NSString).lastPathComponent

        // Validate git repo and resolve gitCommonDir
        let isRepo = try await gitBackend.isGitRepo(path: path)
        var commonDir = path
        if isRepo {
            commonDir = try await gitBackend.gitCommonDir(path: path)
        }

        // Create project
        let project = Project(
            name: name,
            repoRootPath: path,
            gitCommonDir: commonDir,
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

    /// Save UI state synchronously — called from applicationWillTerminate.
    func saveUIStateOnTerminate() {
        try? uiStateRepo.save(appState.uiState)
    }

    // MARK: - Launch Restoration (Task 5.2)

    /// Restore the previously saved UI state: select project, worktree, and window.
    /// Falls back gracefully if any persisted ID no longer exists.
    func restoreState() {
        let uiState = appState.uiState

        // 1. Restore selected project
        guard let projectId = uiState.selectedProjectId,
              appState.projects.contains(where: { $0.id == projectId }) else {
            // No valid project to restore — select first if available
            if let first = appState.projects.first {
                selectProject(first.id)
            }
            return
        }

        appState.uiState.selectedProjectId = projectId

        // 2. Restore selected worktree
        guard let worktreeId = uiState.selectedWorktreeId,
              appState.worktrees.contains(where: { $0.id == worktreeId }) else {
            // No valid worktree — auto-select first for this project
            let worktrees = appState.worktreesForSelectedProject
            if let first = worktrees.first {
                selectWorktree(first.id)
            }
            return
        }

        appState.uiState.selectedWorktreeId = worktreeId

        // Ensure tmux session exists and connect terminal
        if let worktree = appState.worktrees.first(where: { $0.id == worktreeId }) {
            Task {
                await ensureTmuxSession(for: worktree)
                await refreshRuntimeState()

                // Notify terminal to attach
                if let sessionName = worktree.tmuxSessionName {
                    onTerminalSwitch?(sessionName, worktree.path)
                }

                // 3. Restore selected window (after runtime state is loaded)
                if let windowId = uiState.selectedWindowId,
                   appState.runtimeWindows.contains(where: { $0.tmuxWindowId == windowId }) {
                    appState.uiState.selectedWindowId = windowId
                    // Switch tmux to the saved window
                    if let sessionName = worktree.tmuxSessionName {
                        try? await tmuxBackend.selectWindow(sessionId: sessionName, windowId: windowId)
                    }
                }
            }
        }
    }
}
