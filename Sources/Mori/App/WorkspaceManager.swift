import AppKit
import Foundation
import MoriCore
import MoriGit
import MoriPersistence
import MoriTmux

/// Errors specific to WorkspaceManager operations.
enum WorkspaceError: Error, LocalizedError {
    case projectNotFound
    case branchNameEmpty
    case branchNameInvalid(String)

    var errorDescription: String? {
        switch self {
        case .projectNotFound:
            return "Project not found."
        case .branchNameEmpty:
            return "Branch name cannot be empty."
        case .branchNameInvalid(let name):
            return "Invalid branch name: \"\(name)\"."
        }
    }
}

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
    let gitStatusCoordinator: GitStatusCoordinator
    let unreadTracker: UnreadTracker
    let notificationManager: NotificationManager
    let hookRunner: HookRunner
    /// Callback invoked when the terminal should switch to a different session.
    /// Parameters: (sessionName, workingDirectory)
    var onTerminalSwitch: ((String, String) -> Void)?

    /// Callback invoked when the terminal should detach (session killed / no active session).
    var onTerminalDetach: (() -> Void)?

    /// Background coordinated polling task handle.
    private var pollingTask: Task<Void, Never>?

    /// Polling interval in nanoseconds (5 seconds).
    private let pollingInterval: UInt64 = 5_000_000_000

    /// Cache of the latest tmux sessions from the most recent poll.
    /// Used by selectWindow to look up current pane activity timestamps.
    private var latestSessions: [TmuxSession] = []

    /// Previous badge state per window ID — used to detect transitions for notifications.
    private var previousBadges: [String: WindowBadge] = [:]

    /// Debouncer for notification transitions — suppresses re-fire within 30s.
    private var notificationDebouncer = NotificationDebouncer()

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
        self.gitStatusCoordinator = GitStatusCoordinator(gitBackend: gitBackend)
        self.unreadTracker = UnreadTracker()
        self.notificationManager = NotificationManager()
        self.hookRunner = HookRunner(tmuxBackend: tmuxBackend)
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

    // MARK: - Toggle Project Collapse

    func toggleProjectCollapse(_ projectId: UUID) {
        guard let index = appState.projects.firstIndex(where: { $0.id == projectId }) else { return }
        appState.projects[index].isCollapsed.toggle()
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

        // Fire onWorktreeFocus hook
        fireHook(event: .onWorktreeFocus, worktreeId: worktreeId)

        saveUIState()
    }

    // MARK: - Select Window

    func selectWindow(_ windowId: String) {
        appState.uiState.selectedWindowId = windowId

        // Find the window's worktree session to switch tmux window
        if let window = appState.runtimeWindows.first(where: { $0.tmuxWindowId == windowId }),
           let worktree = appState.worktrees.first(where: { $0.id == window.worktreeId }),
           let sessionName = worktree.tmuxSessionName {
            // Keep worktree selection in sync when selecting a window from a different worktree
            if appState.uiState.selectedWorktreeId != worktree.id {
                appState.uiState.selectedWorktreeId = worktree.id
            }
            Task {
                try? await tmuxBackend.selectWindow(sessionId: sessionName, windowId: windowId)
            }
            // Ensure terminal is attached to the right session and focused
            onTerminalSwitch?(sessionName, worktree.path)

            // Clear unread state for this window
            clearUnread(windowId: windowId, worktreeId: worktree.id)

            // Fire onWindowFocus hook
            fireHook(event: .onWindowFocus, worktreeId: worktree.id, windowName: window.title)
        }

        saveUIState()
    }

    /// Clear unread output state for a window and recompute aggregates.
    private func clearUnread(windowId: String, worktreeId: UUID) {
        // Update the last-seen timestamp in the tracker
        if let activity = unreadTracker.currentActivity(windowId: windowId, in: latestSessions) {
            unreadTracker.markSeen(worktreeId: worktreeId, windowId: windowId, activity: activity)
        }

        // Reset hasUnreadOutput on the RuntimeWindow
        if let index = appState.runtimeWindows.firstIndex(where: { $0.tmuxWindowId == windowId }) {
            appState.runtimeWindows[index].hasUnreadOutput = false
            appState.runtimeWindows[index].badge = StatusAggregator.windowBadge(hasUnreadOutput: false)
        }

        // Recompute worktree unread count and project aggregates
        updateUnreadCounts()
        updateAggregatedBadges()
        updateDockBadge()
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
        let sessionName = SessionNaming.sessionName(projectShortName: project.shortName, worktree: "main")
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

    // MARK: - Create Worktree

    /// Create a new worktree for a project: git worktree add, DB save, tmux session, template apply.
    /// Partial failure: if git succeeds but tmux fails, worktree is still saved to DB.
    /// If git fails, no DB write occurs.
    @discardableResult
    func createWorktree(projectId: UUID, branchName: String) async throws -> Worktree {
        // Validate inputs
        let trimmed = branchName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw WorkspaceError.branchNameEmpty
        }

        // Reject branch names with spaces or characters git doesn't allow
        let invalidChars = CharacterSet(charactersIn: " ~^:?*[\\")
        if trimmed.unicodeScalars.contains(where: { invalidChars.contains($0) }) {
            throw WorkspaceError.branchNameInvalid(trimmed)
        }

        guard let project = appState.projects.first(where: { $0.id == projectId }) else {
            throw WorkspaceError.projectNotFound
        }

        let projectSlug = SessionNaming.slugify(project.name)
        let branchSlug = SessionNaming.slugify(trimmed)

        // Compute worktree path: ~/.mori/{project-slug}/{branch-slug}
        let moriDir = (NSHomeDirectory() as NSString).appendingPathComponent(".mori")
        let projectDir = (moriDir as NSString).appendingPathComponent(projectSlug)
        let worktreePath = (projectDir as NSString).appendingPathComponent(branchSlug)

        // Ensure directory tree exists
        try FileManager.default.createDirectory(
            atPath: projectDir,
            withIntermediateDirectories: true
        )

        // Step 1: git worktree add (if this fails, nothing else happens)
        try await gitBackend.addWorktree(
            repoPath: project.repoRootPath,
            path: worktreePath,
            branch: trimmed,
            createBranch: true
        )

        // Step 2: Create Worktree model and save to DB
        let sessionName = SessionNaming.sessionName(projectShortName: project.shortName, worktree: trimmed)
        let worktree = Worktree(
            projectId: projectId,
            name: trimmed,
            path: worktreePath,
            branch: trimmed,
            isMainWorktree: false,
            tmuxSessionName: sessionName,
            status: .active
        )
        try worktreeRepo.save(worktree)

        // Step 3: Create tmux session + apply template (partial failure tolerant)
        do {
            _ = try await tmuxBackend.createSession(name: sessionName, cwd: worktreePath)
            let applicator = TemplateApplicator(tmux: tmuxBackend)
            try await applicator.apply(
                template: TemplateRegistry.basic,
                sessionId: sessionName,
                cwd: worktreePath
            )
        } catch {
            // tmux failure is non-fatal — session will be created on next select
        }

        // Step 4: Update app state
        appState.worktrees.append(worktree)
        selectWorktree(worktree.id)

        // Fire onWorktreeCreate hook
        fireHook(event: .onWorktreeCreate, worktreeId: worktree.id)

        return worktree
    }

    /// Handle create worktree from UI — validates input, calls createWorktree,
    /// and shows error alerts on failure.
    func handleCreateWorktree(branchName: String) async {
        let trimmed = branchName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            showErrorAlert(title: "Invalid Branch Name", message: WorkspaceError.branchNameEmpty.localizedDescription)
            return
        }

        guard let projectId = appState.uiState.selectedProjectId else {
            showErrorAlert(title: "No Project Selected", message: "Please select a project first.")
            return
        }

        do {
            _ = try await createWorktree(projectId: projectId, branchName: trimmed)
            await refreshRuntimeState()
        } catch {
            showErrorAlert(title: "Failed to Create Worktree", message: error.localizedDescription)
        }
    }

    /// Show a user-facing error alert.
    private func showErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Remove Worktree

    /// Remove a worktree with confirmation dialog.
    /// "Remove from Mori" = soft delete (mark unavailable).
    /// "Remove from Mori and delete files" = soft delete + git worktree remove.
    func removeWorktree(worktreeId: UUID) async {
        guard let index = appState.worktrees.firstIndex(where: { $0.id == worktreeId }) else { return }
        let worktree = appState.worktrees[index]

        // Don't allow removing the main worktree
        if worktree.isMainWorktree {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Cannot remove main worktree"
            alert.informativeText = "The main worktree is tied to the project's root directory and cannot be removed."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Remove worktree \"\(worktree.name)\"?"
        alert.informativeText = "This worktree is at \(worktree.path)"
        alert.addButton(withTitle: "Remove from Mori")
        alert.addButton(withTitle: "Remove from Mori and Delete Files")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            // Fire onWorktreeClose hook before cleanup
            fireHook(event: .onWorktreeClose, worktreeId: worktree.id)
            // Soft delete — mark unavailable
            softDeleteWorktree(at: index)

        case .alertSecondButtonReturn:
            // Fire onWorktreeClose hook before cleanup
            fireHook(event: .onWorktreeClose, worktreeId: worktree.id)
            // Hard delete — git worktree remove + soft delete
            softDeleteWorktree(at: index)
            if let project = appState.projects.first(where: { $0.id == worktree.projectId }) {
                do {
                    try await gitBackend.removeWorktree(
                        repoPath: project.repoRootPath,
                        path: worktree.path,
                        force: false
                    )
                } catch {
                    let errorAlert = NSAlert()
                    errorAlert.alertStyle = .warning
                    errorAlert.messageText = "Failed to delete worktree files"
                    errorAlert.informativeText = error.localizedDescription
                    errorAlert.addButton(withTitle: "OK")
                    errorAlert.runModal()
                }
            }

            // Kill tmux session if exists
            if let sessionName = worktree.tmuxSessionName {
                try? await tmuxBackend.killSession(id: sessionName)
            }

        default:
            // Cancel — do nothing
            break
        }
    }

    /// Remove a project and all its worktrees with confirmation dialog.
    func removeProject(projectId: UUID) async {
        guard let project = appState.projects.first(where: { $0.id == projectId }) else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Remove project \"\(project.name)\"?"
        alert.informativeText = "This will remove the project and all its worktrees from Mori. Git repositories on disk will not be deleted."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        // Collect worktrees belonging to this project
        let projectWorktrees = appState.worktrees.filter { $0.projectId == projectId }

        // Kill tmux sessions for all worktrees
        for worktree in projectWorktrees {
            if let sessionName = worktree.tmuxSessionName {
                try? await tmuxBackend.killSession(id: sessionName)
            }
        }

        // Remove worktrees from state and database
        appState.worktrees.removeAll { $0.projectId == projectId }
        for worktree in projectWorktrees {
            try? worktreeRepo.delete(id: worktree.id)
        }

        // Remove project from state and database
        appState.projects.removeAll { $0.id == projectId }
        try? projectRepo.delete(id: projectId)

        // Clear selection if this project was selected
        if appState.uiState.selectedProjectId == projectId {
            appState.uiState.selectedProjectId = nil
            appState.uiState.selectedWorktreeId = nil
            appState.uiState.selectedWindowId = nil

            // Select the first remaining project if any
            if let firstProject = appState.projects.first {
                selectProject(firstProject.id)
            }
            saveUIState()
        }
    }

    /// Mark a worktree as unavailable and persist. Also deselect if currently selected.
    private func softDeleteWorktree(at index: Int) {
        let worktree = appState.worktrees[index]
        let wasSelected = appState.uiState.selectedWorktreeId == worktree.id

        // Remove from state and database
        appState.worktrees.remove(at: index)
        try? worktreeRepo.delete(id: worktree.id)

        // If this was the selected worktree, clear selection
        if wasSelected {
            appState.uiState.selectedWorktreeId = nil
            appState.uiState.selectedWindowId = nil
            let active = appState.worktreesForSelectedProject.filter { $0.status == .active }
            if let first = active.first {
                selectWorktree(first.id)
            }
            saveUIState()
        }
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

        // Build lookup of existing tags to preserve
        let previousTags: [String: WindowTag?] = Dictionary(
            uniqueKeysWithValues: appState.runtimeWindows.map { ($0.tmuxWindowId, $0.tag) }
        )

        var runtimeWindows: [RuntimeWindow] = []

        for session in sessions {
            // Find matching worktree
            guard let worktree = appState.worktrees.first(where: {
                $0.tmuxSessionName == session.name
            }) else { continue }

            for tmuxWindow in session.windows {
                // Preserve existing tag or infer from window name
                let tag: WindowTag? = if let existing = previousTags[tmuxWindow.windowId] {
                    existing
                } else {
                    WindowTag.infer(from: tmuxWindow.name)
                }

                let rw = RuntimeWindow(
                    tmuxWindowId: tmuxWindow.windowId,
                    worktreeId: worktree.id,
                    tmuxWindowIndex: tmuxWindow.windowIndex,
                    title: tmuxWindow.name,
                    paneCount: tmuxWindow.panes.count,
                    tag: tag
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

    // MARK: - Coordinated Polling

    /// Start the coordinated polling timer.
    /// On each 5s tick, triggers both tmux scan and git status concurrently,
    /// then updates AppState with results from both.
    func startPolling() {
        guard pollingTask == nil else { return }
        let interval = self.pollingInterval
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                guard !Task.isCancelled else { break }
                guard let self else { break }
                await self.coordinatedPoll()
            }
        }
    }

    /// Stop the coordinated polling timer.
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Perform a single coordinated poll: tmux scan + git status concurrently.
    func coordinatedPoll() async {
        // Run tmux scan and git status concurrently
        async let tmuxResult: [TmuxSession]? = {
            try? await self.tmuxBackend.scanAll()
        }()
        async let gitResult: [UUID: GitStatusInfo] = {
            await self.gitStatusCoordinator.pollAll(worktrees: self.appState.worktrees)
        }()

        let sessions = await tmuxResult
        let gitStatuses = await gitResult

        // Update runtime state from tmux
        if let sessions {
            // Detect dead sessions and auto-recreate before updating state
            await detectAndRecoverDeadSessions(sessions: sessions)

            latestSessions = sessions

            // Detect unread activity before updating runtime state
            let unreadWindowIds = unreadTracker.processActivity(
                sessions: sessions,
                worktrees: appState.worktrees,
                selectedWindowId: appState.uiState.selectedWindowId
            )

            updateRuntimeState(from: sessions, unreadWindowIds: unreadWindowIds)

            // Detect agent state for agent-tagged windows
            await detectAgentStates(sessions: sessions)
        }

        // Update worktree fields from git status
        updateWorktreeGitStatus(gitStatuses)

        // Roll up unread counts and aggregate badges
        updateUnreadCounts()
        updateAggregatedBadges()

        // Check for notification-worthy badge transitions
        checkNotifications()

        // Update dock badge with aggregate unread count
        updateDockBadge()
    }

    /// Update runtime windows from tmux session data.
    /// Preserves existing `hasUnreadOutput` state and merges newly detected unread windows.
    /// Preserves existing tags or infers them from window names.
    private func updateRuntimeState(from sessions: [TmuxSession], unreadWindowIds: Set<String> = []) {
        // Build lookup of existing unread state and tags
        let previousUnread: [String: Bool] = Dictionary(
            uniqueKeysWithValues: appState.runtimeWindows.map { ($0.tmuxWindowId, $0.hasUnreadOutput) }
        )
        let previousTags: [String: WindowTag?] = Dictionary(
            uniqueKeysWithValues: appState.runtimeWindows.map { ($0.tmuxWindowId, $0.tag) }
        )

        var runtimeWindows: [RuntimeWindow] = []

        for session in sessions {
            guard let worktree = appState.worktrees.first(where: {
                $0.tmuxSessionName == session.name
            }) else { continue }

            for tmuxWindow in session.windows {
                // Window is unread if: newly detected OR was previously unread
                let isUnread = unreadWindowIds.contains(tmuxWindow.windowId)
                    || (previousUnread[tmuxWindow.windowId] ?? false)
                let badge = StatusAggregator.windowBadge(hasUnreadOutput: isUnread)

                // Preserve existing tag or infer from window name
                let tag: WindowTag? = if let existing = previousTags[tmuxWindow.windowId] {
                    existing
                } else {
                    WindowTag.infer(from: tmuxWindow.name)
                }

                let rw = RuntimeWindow(
                    tmuxWindowId: tmuxWindow.windowId,
                    worktreeId: worktree.id,
                    tmuxWindowIndex: tmuxWindow.windowIndex,
                    title: tmuxWindow.name,
                    paneCount: tmuxWindow.panes.count,
                    hasUnreadOutput: isUnread,
                    badge: badge,
                    tag: tag
                )
                runtimeWindows.append(rw)
            }
        }

        appState.runtimeWindows = runtimeWindows
    }

    // MARK: - Agent State Detection

    /// Read agent state from tmux pane options (set by Mori hook scripts).
    /// No capture-pane or process scanning — hooks report state directly.
    /// Also cleans up stale agent state when the agent has exited.
    private func detectAgentStates(sessions: [TmuxSession]) async {
        let now = Date().timeIntervalSince1970

        // Reset worktree agentState before re-aggregating from windows
        for i in appState.worktrees.indices {
            appState.worktrees[i].agentState = .none
        }

        for i in appState.runtimeWindows.indices {
            let rw = appState.runtimeWindows[i]

            guard let (_, tmuxWindow) = findTmuxWindow(
                windowId: rw.tmuxWindowId,
                in: sessions
            ) else { continue }

            guard !tmuxWindow.panes.isEmpty else { continue }

            var windowIsRunning = false
            var windowIsLongRunning = false
            var windowAgentState: AgentState = .none
            var windowDetectedAgent: String? = nil

            for pane in tmuxWindow.panes {
                let isShell = PaneStateDetector.isShellProcess(pane.currentCommand)
                let paneRunning = !isShell && pane.currentCommand != nil
                let paneLongRunning = paneRunning
                    && pane.startTime.map({ now - $0 > PaneStateDetector.longRunningThreshold }) ?? false

                if paneRunning { windowIsRunning = true }
                if paneLongRunning { windowIsLongRunning = true }

                // Read hook-reported agent state from pane options
                if let hookState = pane.agentState {
                    // Always process the state first (agent may have finished
                    // before this poll tick, so pane is back to shell already)
                    let agentState = mapHookState(hookState)
                    if agentStatePriority(agentState) > agentStatePriority(windowAgentState) {
                        windowAgentState = agentState
                    }
                    if let name = pane.agentName {
                        windowDetectedAgent = name
                    }

                    if isShell {
                        // Agent exited — clean up stale options after processing
                        await clearStaleAgentState(paneId: pane.paneId)
                    }
                }
            }

            // Auto-upgrade tag to .agent when a coding agent is detected
            if windowDetectedAgent != nil && rw.tag != .agent {
                appState.runtimeWindows[i].tag = .agent
            }

            appState.runtimeWindows[i].isRunning = windowIsRunning
            appState.runtimeWindows[i].isLongRunning = windowIsLongRunning
            appState.runtimeWindows[i].agentState = windowAgentState
            appState.runtimeWindows[i].detectedAgent = windowDetectedAgent

            let badge = StatusAggregator.windowBadge(
                hasUnreadOutput: rw.hasUnreadOutput,
                isRunning: windowIsRunning,
                isLongRunning: windowIsLongRunning,
                agentState: windowAgentState
            )
            appState.runtimeWindows[i].badge = badge

            if windowAgentState != .none {
                updateWorktreeAgentState(
                    worktreeId: rw.worktreeId,
                    agentState: windowAgentState
                )
            }
        }
    }

    /// Find a tmux window by ID across all sessions.
    private func findTmuxWindow(
        windowId: String,
        in sessions: [TmuxSession]
    ) -> (TmuxSession, TmuxWindow)? {
        for session in sessions {
            if let window = session.windows.first(where: { $0.windowId == windowId }) {
                return (session, window)
            }
        }
        return nil
    }

    /// Map hook state string to AgentState.
    private func mapHookState(_ state: String) -> AgentState {
        switch state {
        case "working": return .running
        case "done": return .completed
        default: return .none
        }
    }

    /// Clear stale pane options when agent has exited (pane returned to shell).
    /// Restores the original window name if saved.
    private func clearStaleAgentState(paneId: String) async {
        try? await tmuxBackend.unsetPaneOption(paneId: paneId, option: "@mori-agent-state")
        try? await tmuxBackend.unsetPaneOption(paneId: paneId, option: "@mori-agent-name")
        // Restore original window name
        let original = try? await tmuxBackend.getPaneOption(paneId: paneId, option: "@mori-original-name")
        if let original, !original.isEmpty {
            // Rename using the pane's parent window
            try? await tmuxBackend.renamePaneWindow(paneId: paneId, newName: original)
            try? await tmuxBackend.unsetPaneOption(paneId: paneId, option: "@mori-original-name")
        }
    }

    /// Update a worktree's agentState to the highest-priority agent state.
    private func updateWorktreeAgentState(worktreeId: UUID, agentState: AgentState) {
        guard let index = appState.worktrees.firstIndex(where: { $0.id == worktreeId }) else { return }
        let current = appState.worktrees[index].agentState
        if agentStatePriority(agentState) > agentStatePriority(current) {
            appState.worktrees[index].agentState = agentState
        }
    }

    /// Priority ordering for agent states.
    private func agentStatePriority(_ state: AgentState) -> Int {
        switch state {
        case .none: return 0
        case .completed: return 1
        case .running: return 2
        case .waitingForInput: return 3
        case .error: return 4
        }
    }

    /// Roll up unread window counts to worktree.unreadCount.
    private func updateUnreadCounts() {
        for i in appState.worktrees.indices {
            let worktreeId = appState.worktrees[i].id
            let unreadCount = appState.runtimeWindows
                .filter { $0.worktreeId == worktreeId && $0.hasUnreadOutput }
                .count
            if appState.worktrees[i].unreadCount != unreadCount {
                appState.worktrees[i].unreadCount = unreadCount
            }
        }
    }

    /// Update worktree git status fields from polled results and persist changes.
    private func updateWorktreeGitStatus(_ statuses: [UUID: GitStatusInfo]) {
        for i in appState.worktrees.indices {
            guard let status = statuses[appState.worktrees[i].id] else { continue }
            let wt = appState.worktrees[i]
            let changed = wt.hasUncommittedChanges != status.isDirty
                || wt.aheadCount != status.ahead
                || wt.behindCount != status.behind

            if changed {
                appState.worktrees[i].hasUncommittedChanges = status.isDirty
                appState.worktrees[i].aheadCount = status.ahead
                appState.worktrees[i].behindCount = status.behind
                // Persist to DB
                try? worktreeRepo.save(appState.worktrees[i])
            }
        }
    }

    /// Aggregate window badges and git status into worktree and project alert states.
    private func updateAggregatedBadges() {
        // Per-worktree aggregation
        for i in appState.worktrees.indices {
            let worktreeId = appState.worktrees[i].id
            let windowBadges = appState.runtimeWindows
                .filter { $0.worktreeId == worktreeId }
                .compactMap { $0.badge }

            let alertState = StatusAggregator.worktreeAlertState(
                windowBadges: windowBadges,
                hasUncommittedChanges: appState.worktrees[i].hasUncommittedChanges
            )
            _ = alertState // Worktree doesn't have an alertState field currently;
            // used at project aggregation level below
        }

        // Per-project aggregation
        for i in appState.projects.indices {
            let projectId = appState.projects[i].id
            let projectWorktrees = appState.worktrees.filter { $0.projectId == projectId }

            // Gather worktree-level alert states
            let worktreeAlerts: [AlertState] = projectWorktrees.map { wt in
                let windowBadges = appState.runtimeWindows
                    .filter { $0.worktreeId == wt.id }
                    .compactMap { $0.badge }
                return StatusAggregator.worktreeAlertState(
                    windowBadges: windowBadges,
                    hasUncommittedChanges: wt.hasUncommittedChanges
                )
            }

            let unreadCounts = projectWorktrees.map { $0.unreadCount }

            let newAlertState = StatusAggregator.projectAlertState(worktreeStates: worktreeAlerts)
            let newUnreadCount = StatusAggregator.projectUnreadCount(worktreeUnreadCounts: unreadCounts)

            if appState.projects[i].aggregateAlertState != newAlertState
                || appState.projects[i].aggregateUnreadCount != newUnreadCount {
                appState.projects[i].aggregateAlertState = newAlertState
                appState.projects[i].aggregateUnreadCount = newUnreadCount
                try? projectRepo.save(appState.projects[i])
            }
        }
    }

    // MARK: - Notifications

    /// Compare current window badges with previous poll cycle and fire notifications
    /// for approved transitions via NotificationDebouncer.
    private func checkNotifications() {
        let now = Date()
        for rw in appState.runtimeWindows {
            let oldBadge = previousBadges[rw.tmuxWindowId]
            let newBadge = rw.badge ?? .idle

            if let event = notificationDebouncer.shouldNotify(
                windowId: rw.tmuxWindowId,
                oldBadge: oldBadge,
                newBadge: newBadge,
                now: now
            ) {
                // Find parent worktree name
                let worktreeName = appState.worktrees
                    .first(where: { $0.id == rw.worktreeId })?.name ?? "Unknown"

                let agentDisplayName = rw.detectedAgent
                    .flatMap { AgentHookConfigurator.agentDisplayNames[$0] }

                notificationManager.notify(
                    event,
                    windowTitle: rw.title,
                    worktreeName: worktreeName,
                    windowId: rw.tmuxWindowId,
                    worktreeId: rw.worktreeId.uuidString,
                    agentName: agentDisplayName
                )
            }

            previousBadges[rw.tmuxWindowId] = newBadge
        }
    }

    // MARK: - Dock Badge

    /// Update the dock tile badge with aggregate unread count across all projects.
    func updateDockBadge() {
        let totalUnread = appState.projects.reduce(0) { $0 + $1.aggregateUnreadCount }
        NSApp.dockTile.badgeLabel = totalUnread > 0 ? "\(totalUnread)" : nil
    }

    // MARK: - Window / Pane Operations

    /// Create a new tmux window in the current worktree's session.
    /// Recreates the session if it was killed (e.g. last window closed via tmux).
    func createNewWindow() async {
        guard let worktree = selectedWorktree,
              let sessionName = worktree.tmuxSessionName else { return }
        do {
            await ensureTmuxSession(for: worktree)
            _ = try await tmuxBackend.createWindow(sessionId: sessionName, name: nil, cwd: worktree.path)
            await refreshRuntimeState()
            // Re-attach terminal to the (possibly recreated) session
            onTerminalSwitch?(sessionName, worktree.path)

            // Fire onWindowCreate hook
            fireHook(event: .onWindowCreate, worktreeId: worktree.id)
        } catch {
            showErrorAlert(title: "Failed to create window", message: error.localizedDescription)
        }
    }

    /// Split the active pane in the current session.
    func splitCurrentPane(horizontal: Bool) async {
        guard let worktree = selectedWorktree,
              let sessionName = worktree.tmuxSessionName else { return }

        do {
            // Target the session — tmux splits whatever pane is currently active.
            // Don't use cached findActivePaneId which can be stale between polls.
            _ = try await tmuxBackend.splitPane(
                sessionId: sessionName,
                paneId: "",
                horizontal: horizontal,
                cwd: worktree.path
            )
            await refreshRuntimeState()
        } catch {
            showErrorAlert(title: "Failed to split pane", message: error.localizedDescription)
        }
    }

    /// Switch to the next tmux window in the current session.
    func nextWindow() {
        navigateWindow(offset: 1)
    }

    /// Switch to the previous tmux window in the current session.
    func previousWindow() {
        navigateWindow(offset: -1)
    }

    /// Close the active tmux pane. If it is the last pane in the window the
    /// window closes; if it is the last window the session is killed.
    func closeCurrentPane() async {
        guard let worktree = selectedWorktree,
              let sessionName = worktree.tmuxSessionName else { return }

        do {
            // Target the session — tmux kills whatever pane is currently active.
            // Don't use cached findActivePaneId which can be stale between polls.
            try await tmuxBackend.killPane(sessionId: sessionName, paneId: sessionName)
            await refreshRuntimeState()

            // If the session was killed (last pane in last window), detach
            let stillHasWindows = appState.runtimeWindows.contains { $0.worktreeId == worktree.id }
            if !stillHasWindows {
                appState.uiState.selectedWindowId = nil
                onTerminalDetach?()
            }
        } catch {
            showErrorAlert(title: "Failed to close pane", message: error.localizedDescription)
        }
    }

    /// Close the currently selected tmux window.
    /// If it's the last window, kills the session and shows empty state.
    func closeCurrentWindow() async {
        guard let worktree = selectedWorktree,
              let sessionName = worktree.tmuxSessionName,
              let windowId = appState.uiState.selectedWindowId else { return }

        let windowsInSession = appState.runtimeWindows.filter { $0.worktreeId == worktree.id }

        // Fire onWindowClose hook before kill
        let windowTitle = appState.runtimeWindows
            .first(where: { $0.tmuxWindowId == windowId })?.title ?? ""
        fireHook(event: .onWindowClose, worktreeId: worktree.id, windowName: windowTitle)

        do {
            if windowsInSession.count <= 1 {
                // Last window — kill the entire session and detach terminal
                try await tmuxBackend.killSession(id: sessionName)
                appState.uiState.selectedWindowId = nil
                appState.runtimeWindows.removeAll { $0.worktreeId == worktree.id }
                onTerminalDetach?()
            } else {
                try await tmuxBackend.killWindow(sessionId: sessionName, windowId: windowId)
                appState.uiState.selectedWindowId = nil
                await refreshRuntimeState()
                // Auto-select the first remaining window
                if let first = appState.runtimeWindows.first(where: { $0.worktreeId == worktree.id }) {
                    selectWindow(first.tmuxWindowId)
                }
            }
        } catch {
            showErrorAlert(title: "Failed to close window", message: error.localizedDescription)
        }
    }

    /// Close a specific tmux window by its ID (from sidebar context menu).
    func closeWindow(windowId: String) async {
        guard let rw = appState.runtimeWindows.first(where: { $0.tmuxWindowId == windowId }),
              let worktree = appState.worktrees.first(where: { $0.id == rw.worktreeId }),
              let sessionName = worktree.tmuxSessionName else { return }

        let windowsInSession = appState.runtimeWindows.filter { $0.worktreeId == worktree.id }

        fireHook(event: .onWindowClose, worktreeId: worktree.id, windowName: rw.title)

        do {
            if windowsInSession.count <= 1 {
                try await tmuxBackend.killSession(id: sessionName)
                appState.runtimeWindows.removeAll { $0.worktreeId == worktree.id }
                if worktree.id == appState.uiState.selectedWorktreeId {
                    appState.uiState.selectedWindowId = nil
                    onTerminalDetach?()
                }
            } else {
                try await tmuxBackend.killWindow(sessionId: sessionName, windowId: windowId)
                await refreshRuntimeState()
                if windowId == appState.uiState.selectedWindowId {
                    appState.uiState.selectedWindowId = nil
                    if let first = appState.runtimeWindows.first(where: { $0.worktreeId == worktree.id }) {
                        selectWindow(first.tmuxWindowId)
                    }
                }
            }
        } catch {
            showErrorAlert(title: "Failed to close window", message: error.localizedDescription)
        }
    }

    // MARK: - Window Navigation Helpers

    private var selectedWorktree: Worktree? {
        guard let id = appState.uiState.selectedWorktreeId else { return nil }
        return appState.worktrees.first { $0.id == id }
    }

    /// Whether a worktree is currently selected (used to decide empty-state UI).
    var hasSelectedWorktree: Bool {
        selectedWorktree != nil
    }

    /// Recreate the tmux session for the current worktree and re-attach the terminal.
    func reconnectCurrentSession() async {
        guard let worktree = selectedWorktree else { return }
        await ensureTmuxSession(for: worktree)
        await refreshRuntimeState()
        if let sessionName = worktree.tmuxSessionName {
            onTerminalSwitch?(sessionName, worktree.path)
        }
    }

    private func navigateWindow(offset: Int) {
        guard let worktree = selectedWorktree else { return }
        let windows = appState.runtimeWindows
            .filter { $0.worktreeId == worktree.id }
            .sorted { $0.tmuxWindowIndex < $1.tmuxWindowIndex }
        guard !windows.isEmpty else { return }

        let currentIndex = windows.firstIndex(where: { $0.tmuxWindowId == appState.uiState.selectedWindowId }) ?? 0
        let newIndex = (currentIndex + offset + windows.count) % windows.count
        selectWindow(windows[newIndex].tmuxWindowId)
    }

    private func findActivePaneId(sessionName: String) -> String? {
        guard let session = latestSessions.first(where: { $0.name == sessionName }) else { return nil }
        for window in session.windows {
            if let pane = window.panes.first(where: { $0.isActive }) {
                return pane.paneId
            }
        }
        return session.windows.first?.panes.first?.paneId
    }

    /// Open a CLI tool (e.g. lazygit, yazi) in a new tmux window at the active pane's cwd.
    /// The window auto-names after the tool and closes when the tool exits.
    func openToolWindow(command: String) async {
        guard let worktree = selectedWorktree,
              let sessionName = worktree.tmuxSessionName else { return }

        // Resolve cwd from the active pane, falling back to worktree path
        let cwd = activePaneCwd() ?? worktree.path

        do {
            await ensureTmuxSession(for: worktree)
            let window = try await tmuxBackend.createWindow(sessionId: sessionName, name: command, cwd: cwd)
            try await tmuxBackend.sendKeys(sessionId: sessionName, paneId: window.windowId, keys: command)
            await refreshRuntimeState()
            onTerminalSwitch?(sessionName, worktree.path)
        } catch {
            showErrorAlert(title: "Failed to open \(command)", message: error.localizedDescription)
        }
    }

    /// Returns the cwd of the currently active pane, if available.
    private func activePaneCwd() -> String? {
        guard let windowId = appState.uiState.selectedWindowId else { return nil }
        let panes = appState.panes(forWindow: windowId)
        return panes.first(where: { $0.isActive })?.cwd ?? panes.first?.cwd
    }

    // MARK: - Pane Navigation & Management

    /// Navigate to a pane by direction (up/down/left/right/next/previous).
    func navigatePane(direction: PaneDirection) async {
        guard let worktree = selectedWorktree,
              let sessionName = worktree.tmuxSessionName else { return }
        do {
            try await tmuxBackend.navigatePane(sessionId: sessionName, direction: direction)
        } catch {
            // Non-fatal — pane may not exist in that direction
        }
    }

    /// Resize the active pane in the given direction.
    func resizePane(direction: PaneDirection, amount: Int = 10) async {
        guard let worktree = selectedWorktree,
              let sessionName = worktree.tmuxSessionName else { return }
        do {
            try await tmuxBackend.resizePane(sessionId: sessionName, direction: direction, amount: amount)
        } catch {
            // Non-fatal
        }
    }

    /// Toggle zoom on the active pane.
    func togglePaneZoom() async {
        guard let worktree = selectedWorktree,
              let sessionName = worktree.tmuxSessionName else { return }
        do {
            try await tmuxBackend.togglePaneZoom(sessionId: sessionName)
        } catch {
            // Non-fatal
        }
    }

    /// Equalize all pane sizes in the active window.
    func equalizePanes() async {
        guard let worktree = selectedWorktree,
              let sessionName = worktree.tmuxSessionName else { return }
        do {
            try await tmuxBackend.equalizePanes(sessionId: sessionName)
        } catch {
            // Non-fatal
        }
    }

    // MARK: - Window Index Navigation

    /// Select a tmux window by 1-based index (Cmd+1 through Cmd+9).
    /// Cmd+9 selects the last window regardless of count.
    func selectWindowByIndex(_ index: Int) {
        let windows = appState.windowsForSelectedWorktree
        guard !windows.isEmpty else { return }

        let targetIndex: Int
        if index == 9 {
            targetIndex = windows.count - 1
        } else {
            targetIndex = index - 1
        }

        guard targetIndex >= 0, targetIndex < windows.count else { return }
        selectWindow(windows[targetIndex].tmuxWindowId)
    }

    // MARK: - Worktree Cycling

    /// Cycle to the next or previous worktree (Ctrl+Tab / Ctrl+Shift+Tab).
    func cycleWorktree(forward: Bool) {
        guard let projectId = appState.uiState.selectedProjectId else { return }
        let projectWorktrees = appState.worktrees
            .filter { $0.projectId == projectId }
        guard !projectWorktrees.isEmpty else { return }

        let currentIndex = projectWorktrees.firstIndex(where: {
            $0.id == appState.uiState.selectedWorktreeId
        }) ?? 0

        let offset = forward ? 1 : -1
        let newIndex = (currentIndex + offset + projectWorktrees.count) % projectWorktrees.count
        selectWorktree(projectWorktrees[newIndex].id)
    }

    // MARK: - Session Death Detection

    /// Called during polling to detect and handle dead sessions for active worktrees.
    /// Auto-recreates sessions and re-attaches if the selected worktree's session died.
    func detectAndRecoverDeadSessions(sessions: [TmuxSession]) async {
        guard let worktree = appState.selectedWorktree,
              let sessionName = worktree.tmuxSessionName else { return }

        let sessionAlive = sessions.contains { $0.name == sessionName }
        let hadWindows = appState.runtimeWindows.contains { $0.worktreeId == worktree.id }

        if !sessionAlive && hadWindows {
            // Session died — auto-recreate and re-attach
            _ = try? await tmuxBackend.createSession(name: sessionName, cwd: worktree.path)
            onTerminalSwitch?(sessionName, worktree.path)
        }
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

    // MARK: - Hook Helpers

    /// Build a HookContext from the current state for a given worktree.
    private func buildHookContext(
        worktree: Worktree,
        project: Project,
        windowName: String = ""
    ) -> HookContext {
        HookContext(
            projectName: project.name,
            worktreeName: worktree.name,
            sessionName: worktree.tmuxSessionName ?? "",
            windowName: windowName,
            cwd: worktree.path
        )
    }

    /// Fire a hook event for the given worktree if a matching project is found.
    private func fireHook(event: HookEvent, worktreeId: UUID, windowName: String = "") {
        guard let worktree = appState.worktrees.first(where: { $0.id == worktreeId }),
              let project = appState.projects.first(where: { $0.id == worktree.projectId }) else {
            return
        }
        let context = buildHookContext(worktree: worktree, project: project, windowName: windowName)
        hookRunner.fire(event: event, context: context, projectRootPath: project.repoRootPath)
    }
}
