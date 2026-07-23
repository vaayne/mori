import AppKit
import Foundation
import MoriCore
import MoriGit
import MoriPersistence
import MoriTmux

/// Errors specific to WorkspaceManager operations.
enum WorkspaceError: Error, LocalizedError {
    case projectNotFound
    case projectNotRemote
    case worktreeNotFound
    case cannotDeleteMainWorktree
    case branchNameEmpty
    case branchNameInvalid(String)
    case remoteHostEmpty
    case remotePathEmpty
    case remoteTmuxUnavailable(String)
    case remotePasswordEmpty
    case remotePasswordPersistFailed(String)
    case remoteSessionNameEmpty
    case remoteSessionNotFound(String)
    case remoteSessionAlreadyAttached(String)
    case unsafeWorkspaceDeletion(String)
    case deletionInProgress
    case pullRequestUnavailable(Int)
    case pullRequestRequiresGitRepo

    var errorDescription: String? {
        switch self {
        case .projectNotFound:
            return "Project not found."
        case .projectNotRemote:
            return "Project is not configured as a remote SSH project."
        case .worktreeNotFound:
            return "Worktree not found."
        case .cannotDeleteMainWorktree:
            return "The main worktree cannot be deleted."
        case .branchNameEmpty:
            return "Branch name cannot be empty."
        case .branchNameInvalid(let name):
            return "Invalid branch name: \"\(name)\"."
        case .remoteHostEmpty:
            return "Remote host cannot be empty."
        case .remotePathEmpty:
            return "Remote repository path cannot be empty."
        case .remoteTmuxUnavailable(let host):
            return "tmux is not available on remote host \"\(host)\"."
        case .remotePasswordEmpty:
            return "Password is required for password authentication."
        case .remotePasswordPersistFailed(let message):
            return "Failed to persist SSH password: \(message)"
        case .remoteSessionNameEmpty:
            return .localized("Remote tmux session name cannot be empty.")
        case .remoteSessionNotFound(let name):
            return String(
                format: .localized("tmux session \"%@\" was not found on the remote host."),
                name
            )
        case .remoteSessionAlreadyAttached(let name):
            return String(
                format: .localized("tmux session \"%@\" is already attached to another workspace. Choose a different session or create a new one."),
                name
            )
        case .unsafeWorkspaceDeletion(let reason):
            return reason
        case .deletionInProgress:
            return .localized("This workspace is already being deleted.")
        case .pullRequestUnavailable(let number):
            return String(
                format: .localized("Could not resolve pull request #%d. Check that gh is installed, authenticated, and the PR exists."),
                number
            )
        case .pullRequestRequiresGitRepo:
            return .localized("Creating a workspace from a pull request requires a git repository.")
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
    /// Local tmux backend.
    let tmuxBackend: TmuxBackend
    /// Local git backend.
    let gitBackend: GitBackend
    let gitStatusCoordinator: GitStatusCoordinator
    /// Read-only GitHub PR lookups for the selected worktree (local only).
    let gitHubBackend = GitHubBackend()
    let unreadTracker: UnreadTracker
    let notificationManager: NotificationManager
    let hookRunner: HookRunner
    /// Callback invoked when the terminal should switch to a different session.
    /// Parameters: (sessionName, workingDirectory, location)
    var onTerminalSwitch: ((String, String, WorkspaceLocation) -> Void)?

    /// Callback invoked when the terminal should detach (session killed / no active session).
    var onTerminalDetach: (() -> Void)?

    /// Callback invoked when a tmux backend should be (re)configured for runtime
    /// options (theme/proxy/terminal capabilities).
    var onSessionCreated: ((TmuxBackend) async -> Void)?

    /// Background coordinated polling task handle.
    private var pollingTask: Task<Void, Never>?

    /// Polling interval in nanoseconds (5 seconds).
    private let pollingInterval: UInt64 = 5_000_000_000

    /// Remote endpoint backend caches keyed by `WorkspaceLocation.endpointKey`.
    private var remoteTmuxBackends: [String: TmuxBackend] = [:]
    private var remoteGitBackends: [String: GitBackend] = [:]

    /// Cache of latest sessions by endpoint key from the most recent poll.
    private var latestSessionsByEndpoint: [String: [TmuxSession]] = [:]

    /// Avoid repeatedly showing the same Keychain access alert.
    private var keychainAccessAlertedEndpoints: Set<String> = []

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
        self.gitStatusCoordinator = GitStatusCoordinator()
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
        // Self-heal: a transient status in the store means a create/delete was
        // interrupted (or an older build persisted one). Left as-is the row
        // would be permanently unselectable and undeletable.
        for i in allWorktrees.indices where allWorktrees[i].status.isTransient {
            allWorktrees[i].status = .active
            try? worktreeRepo.save(allWorktrees[i])
        }
        appState.worktrees = allWorktrees
        appState.uiState = try uiStateRepo.fetch()

        // Backfill missing tmux session names from legacy data so every
        // worktree can be mapped to a stable tmux session.
        backfillWorktreeSessionNamesIfNeeded()
        normalizeConflictingSessionBindingsIfNeeded()

        // Validate project paths — mark unavailable if path no longer exists
        validateProjectPaths()
    }

    /// On first launch (no projects), create a default "Home" workspace at $HOME.
    func createHomeWorkspaceIfNeeded() async {
        guard appState.projects.isEmpty else { return }
        let homePath = NSHomeDirectory()
        let project = try? await addProject(path: homePath)
        guard var p = project,
              let pIdx = appState.projects.firstIndex(where: { $0.id == p.id }) else { return }
        // Rename project and worktree to "Home" for a friendlier first impression
        p.name = "Home"
        appState.projects[pIdx] = p
        try? projectRepo.save(p)

        if var wt = appState.worktrees.first(where: { $0.projectId == p.id }),
           let wIdx = appState.worktrees.firstIndex(where: { $0.id == wt.id }) {
            wt.name = "Home"
            appState.worktrees[wIdx] = wt
            try? worktreeRepo.save(wt)
        }
    }

    private func backfillWorktreeSessionNamesIfNeeded() {
        for i in appState.worktrees.indices {
            let existing = appState.worktrees[i].tmuxSessionName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard existing?.isEmpty != false else { continue }
            guard let project = appState.projects.first(where: { $0.id == appState.worktrees[i].projectId }) else {
                continue
            }
            let worktreeName = appState.worktrees[i].branch ?? appState.worktrees[i].name
            let sessionName = SessionNaming.sessionName(
                projectShortName: project.shortName,
                worktree: worktreeName
            )
            appState.worktrees[i].tmuxSessionName = sessionName
            try? worktreeRepo.save(appState.worktrees[i])
        }
    }

    /// Ensure session bindings are unique per endpoint to prevent collisions
    /// where two worktrees point to the same remote tmux session.
    private func normalizeConflictingSessionBindingsIfNeeded() {
        var seenKeys = Set<String>()
        for i in appState.worktrees.indices {
            guard let sessionName = appState.worktrees[i].tmuxSessionName?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !sessionName.isEmpty else {
                continue
            }

            let endpoint = endpointKey(for: appState.worktrees[i])
            let key = "\(endpoint)|\(sessionName)"
            if seenKeys.insert(key).inserted {
                continue
            }

            guard let project = projectForWorktree(appState.worktrees[i]) else { continue }
            let worktreeName = appState.worktrees[i].branch ?? appState.worktrees[i].name
            let canonicalBase = SessionNaming.sessionName(
                projectShortName: project.shortName,
                worktree: worktreeName
            )

            var candidate = canonicalBase
            var suffix = 2
            while seenKeys.contains("\(endpoint)|\(candidate)") {
                candidate = "\(canonicalBase)-\(suffix)"
                suffix += 1
            }

            appState.worktrees[i].tmuxSessionName = candidate
            seenKeys.insert("\(endpoint)|\(candidate)")
            try? worktreeRepo.save(appState.worktrees[i])
        }
    }

    /// Check each worktree path and mark as unavailable if the directory is gone.
    private func validateProjectPaths() {
        let fm = FileManager.default
        for i in appState.worktrees.indices {
            // Remote worktrees are validated via SSH git/tmux operations, not local filesystem checks.
            if appState.worktrees[i].resolvedLocation != .local {
                continue
            }
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
        // If there are no local worktrees, local tmux isn't required at startup.
        let hasLocalWorktree = appState.worktrees.contains { $0.resolvedLocation == .local }
        guard hasLocalWorktree else {
            isTmuxAvailable = true
            return true
        }

        let available = await tmuxBackend.isAvailable()
        isTmuxAvailable = available
        return available
    }

    private func location(for project: Project) -> WorkspaceLocation {
        project.resolvedLocation
    }

    private func location(for worktree: Worktree) -> WorkspaceLocation {
        // Single source of truth for endpoint resolution:
        // worktree endpoint overrides project only when explicitly persisted.
        if let project = appState.projects.first(where: { $0.id == worktree.projectId }) {
            return worktree.location ?? project.resolvedLocation
        }
        return worktree.resolvedLocation
    }

    private func backendCacheKey(for ssh: SSHWorkspaceLocation) -> String {
        "ssh:\(ssh.endpointKey):\(ssh.authMethod.rawValue)"
    }

    private func invalidateRemoteBackends(for ssh: SSHWorkspaceLocation) {
        let key = backendCacheKey(for: ssh)
        remoteTmuxBackends.removeValue(forKey: key)
        remoteGitBackends.removeValue(forKey: key)
    }

    private func tmuxBackend(for location: WorkspaceLocation) -> TmuxBackend {
        switch location {
        case .local:
            return tmuxBackend
        case .ssh(let ssh):
            let key = backendCacheKey(for: ssh)
            if let cached = remoteTmuxBackends[key] {
                return cached
            }
            let password = ssh.authMethod == .password
                ? loadStoredPassword(for: ssh)
                : nil
            let backend = TmuxBackend(
                runner: TmuxCommandRunner(
                    sshConfig: TmuxSSHConfig(
                        host: ssh.host,
                        user: ssh.user,
                        port: ssh.port,
                        sshOptions: SSHControlOptions.sshOptions(for: ssh),
                        askpassPassword: password
                    )
                )
            )
            remoteTmuxBackends[key] = backend
            return backend
        }
    }

    private func tmuxBackend(for worktree: Worktree) -> TmuxBackend {
        tmuxBackend(for: location(for: worktree))
    }

    private func gitBackend(for location: WorkspaceLocation) -> GitBackend {
        switch location {
        case .local:
            return gitBackend
        case .ssh(let ssh):
            let key = backendCacheKey(for: ssh)
            if let cached = remoteGitBackends[key] {
                return cached
            }
            let password = ssh.authMethod == .password
                ? loadStoredPassword(for: ssh)
                : nil
            let backend = GitBackend(
                runner: GitCommandRunner(
                    sshConfig: GitSSHConfig(
                        host: ssh.host,
                        user: ssh.user,
                        port: ssh.port,
                        sshOptions: SSHControlOptions.sshOptions(for: ssh),
                        askpassPassword: password
                    )
                )
            )
            remoteGitBackends[key] = backend
            return backend
        }
    }

    private func gitBackend(for worktree: Worktree) -> GitBackend {
        gitBackend(for: location(for: worktree))
    }

    private func loadStoredPassword(for ssh: SSHWorkspaceLocation) -> String? {
        do {
            let password = try SSHCredentialStore.password(for: ssh)
            if password != nil {
                keychainAccessAlertedEndpoints.remove(ssh.endpointKey)
            }
            return password
        } catch {
            let endpointKey = ssh.endpointKey
            if !keychainAccessAlertedEndpoints.contains(endpointKey) {
                keychainAccessAlertedEndpoints.insert(endpointKey)
                presentKeychainAccessError(error, for: ssh)
            }
            return nil
        }
    }

    private func presentKeychainAccessError(_ error: Error, for ssh: SSHWorkspaceLocation) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = .localized("Failed to access SSH password from Keychain")
        alert.informativeText = String(
            format: .localized("Mori could not read credentials for \"%@\". Re-enter credentials or unlock Keychain.\n\n%@"),
            ssh.target,
            error.localizedDescription
        )
        alert.addButton(withTitle: .localized("OK"))
        alert.runModal()
    }

    private func projectForWorktree(_ worktree: Worktree) -> Project? {
        appState.projects.first(where: { $0.id == worktree.projectId })
    }

    private func namespacedWindowId(rawWindowId: String, worktree: Worktree) -> String {
        WorkspaceEndpoint.namespacedWindowId(rawWindowId: rawWindowId, location: location(for: worktree))
    }

    private func rawWindowId(from runtimeWindow: RuntimeWindow) -> String {
        runtimeWindow.tmuxWindowRawId ?? runtimeWindow.tmuxWindowId
    }

    func tmuxBackendForWorktree(_ worktree: Worktree) -> TmuxBackend {
        tmuxBackend(for: worktree)
    }

    func allTmuxBackends() -> [TmuxBackend] {
        [tmuxBackend] + Array(remoteTmuxBackends.values)
    }

    func rawTmuxWindowId(from runtimeWindow: RuntimeWindow) -> String {
        rawWindowId(from: runtimeWindow)
    }

    func sessionsForWorktree(_ worktree: Worktree) -> [TmuxSession] {
        sessionsForEndpoint(of: worktree)
    }

    func moriPaneEnvironment(for worktree: Worktree) -> [String: String] {
        var environment = [
            "MORI_WORKTREE": worktree.name,
        ]
        if let project = projectForWorktree(worktree) {
            environment["MORI_PROJECT"] = project.name
        }
        if let sessionName = worktree.tmuxSessionName {
            environment["MORI_SESSION_NAME"] = sessionName
        }
        return environment
    }

    private func endpointKey(for worktree: Worktree) -> String {
        location(for: worktree).endpointKey
    }

    private func sessionsForEndpoint(of worktree: Worktree) -> [TmuxSession] {
        latestSessionsByEndpoint[endpointKey(for: worktree)] ?? []
    }

    private func scanSessionsByEndpoint() async -> [String: [TmuxSession]] {
        let locations = Set(appState.worktrees.map { location(for: $0) })
        guard !locations.isEmpty else { return [:] }

        var sessionsByEndpoint: [String: [TmuxSession]] = [:]
        for loc in locations {
            let tmux = tmuxBackend(for: loc)
            let sessions = (try? await tmux.scanAll()) ?? []
            sessionsByEndpoint[loc.endpointKey] = sessions
        }
        return sessionsByEndpoint
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
        // Transient placeholders (creating/deleting) have no session to attach.
        if let transient = appState.worktrees.first(where: { $0.id == worktreeId }),
           transient.status.isTransient {
            return
        }
        appState.uiState.selectedWorktreeId = worktreeId
        appState.uiState.selectedWindowId = nil

        // Track last active time
        if let index = appState.worktrees.firstIndex(where: { $0.id == worktreeId }) {
            appState.worktrees[index].lastActiveAt = Date()
            try? worktreeRepo.save(appState.worktrees[index])
        }

        guard let worktree = appState.worktrees.first(where: { $0.id == worktreeId }) else { return }

        // Sync selectedProjectId from the worktree's projectId (enables cross-project selection in task mode)
        if appState.uiState.selectedProjectId != worktree.projectId {
            appState.uiState.selectedProjectId = worktree.projectId
        }

        // Ensure tmux session exists, check branch, then switch terminal
        Task {
            await refreshWorktreeBranch(worktreeId: worktreeId)
            let sessionReady = await ensureTmuxSession(for: worktree, showErrors: true)
            if sessionReady {
                await onSessionCreated?(tmuxBackend(for: worktree))
            }
            await refreshRuntimeState()

            // Notify terminal to switch to this worktree's session
            if sessionReady, let sessionName = worktree.tmuxSessionName {
                onTerminalSwitch?(sessionName, worktree.path, location(for: worktree))
            } else {
                onTerminalDetach?()
            }
        }

        // Fire onWorktreeFocus hook
        fireHook(event: .onWorktreeFocus, worktreeId: worktreeId)

        // Refresh the GitHub PR strip for the newly selected worktree.
        Task { await refreshPullRequest(for: worktreeId, force: true) }

        saveUIState()
    }

    // MARK: - GitHub PR

    /// Wall-clock of the last `gh` fetch per worktree, to keep the 5s poll from
    /// spawning a subprocess every tick. CI/review state moves on a minute scale.
    private var lastPullRequestFetch: [UUID: Date] = [:]
    private static let pullRequestThrottle: TimeInterval = 60
    private var pullRequestSweepInFlight = false
    private var lastProjectPullRequestFetch: [UUID: Date] = [:]
    /// Tighter than the per-worktree throttle: the sweep costs one `gh pr list`
    /// per project regardless of worktree count, so it can afford to be fresh.
    private static let projectPullRequestThrottle: TimeInterval = 20

    /// Best-effort sweep so sidebar PR badges populate and stay fresh without a
    /// selection. One repo-wide `gh pr list` per local project (throttled),
    /// mapped onto worktrees by head branch. A worktree whose badge says "open"
    /// but whose branch is absent from the list just transitioned (merged or
    /// closed) — resolve its terminal state once via the per-branch `gh pr view`
    /// path, which sees non-open PRs. The in-flight guard keeps overlapping
    /// poll ticks from stacking sweeps.
    private func sweepPullRequests() async {
        guard !pullRequestSweepInFlight else { return }
        pullRequestSweepInFlight = true
        defer { pullRequestSweepInFlight = false }

        for project in appState.projects {
            guard case .local = location(for: project), !project.repoRootPath.isEmpty else { continue }
            let worktrees = appState.worktrees.filter {
                $0.projectId == project.id && $0.branch != nil && !$0.status.isTransient
            }
            guard !worktrees.isEmpty else { continue }

            if let last = lastProjectPullRequestFetch[project.id],
               Date().timeIntervalSince(last) < Self.projectPullRequestThrottle { continue }
            lastProjectPullRequestFetch[project.id] = Date()

            // nil = fetch failed (gh missing, auth, network): keep whatever
            // badges we have rather than clearing or "resolving" them.
            guard let openByBranch = await gitHubBackend.openPullRequestsByBranch(
                directory: project.repoRootPath
            ) else { continue }

            for worktree in worktrees {
                guard let branch = worktree.branch else { continue }
                if let info = openByBranch[branch] {
                    if appState.pullRequests[worktree.id] != info {
                        appState.pullRequests[worktree.id] = info
                    }
                } else if appState.pullRequests[worktree.id]?.state == .open {
                    // Un-forced: the per-worktree throttle caps this fallback for
                    // the rare branch gh names differently than the API head ref.
                    await refreshPullRequest(for: worktree.id)
                }
            }
        }
    }

    /// Fetch the PR for a worktree's branch and update `appState.pullRequests`.
    /// Local worktrees only; remote (SSH) worktrees are skipped. Best-effort —
    /// a missing gh, no PR, or any error just leaves the cache entry empty.
    /// `force` bypasses the throttle (used on selection for an immediate refresh).
    func refreshPullRequest(for worktreeId: UUID, force: Bool = false) async {
        guard let worktree = appState.worktrees.first(where: { $0.id == worktreeId }),
              !worktree.status.isTransient,
              let branch = worktree.branch,
              case .local = location(for: worktree) else { return }

        if !force, let last = lastPullRequestFetch[worktreeId],
           Date().timeIntervalSince(last) < Self.pullRequestThrottle { return }
        lastPullRequestFetch[worktreeId] = Date()

        let info = await gitHubBackend.pullRequest(forBranch: branch, directory: worktree.path)
        if appState.pullRequests[worktreeId] != info {
            appState.pullRequests[worktreeId] = info
        }
    }

    // MARK: - Select Window

    func selectWindow(_ windowId: String) {
        appState.uiState.selectedWindowId = windowId

        // Find the window's worktree session to switch tmux window
        if let window = appState.runtimeWindows.first(where: { $0.tmuxWindowId == windowId }),
           let worktree = appState.worktrees.first(where: { $0.id == window.worktreeId }),
           let sessionName = worktree.tmuxSessionName {
            // Keep worktree and project selection in sync when selecting a window
            // (important for task mode where windows can span projects)
            if appState.uiState.selectedWorktreeId != worktree.id {
                appState.uiState.selectedWorktreeId = worktree.id
            }
            if appState.uiState.selectedProjectId != worktree.projectId {
                appState.uiState.selectedProjectId = worktree.projectId
            }
            let tmux = tmuxBackend(for: worktree)
            let rawWindowId = rawWindowId(from: window)
            Task {
                try? await tmux.selectWindow(sessionId: sessionName, windowId: rawWindowId)
            }
            // Ensure terminal is attached to the right session and focused
            onTerminalSwitch?(sessionName, worktree.path, location(for: worktree))

            // Clear unread state for this window
            clearUnread(windowId: rawWindowId, worktree: worktree)

            // Fire onWindowFocus hook
            fireHook(event: .onWindowFocus, worktreeId: worktree.id, windowName: window.title)
        }

        saveUIState()
    }

    func selectPane(_ paneId: String) {
        guard let pane = appState.runtimePanes.first(where: { $0.tmuxPaneId == paneId }),
              let window = appState.runtimeWindows.first(where: { $0.tmuxWindowId == pane.tmuxWindowId }),
              let worktree = appState.worktrees.first(where: { $0.id == window.worktreeId }),
              let sessionName = worktree.tmuxSessionName else {
            return
        }

        appState.uiState.selectedWindowId = window.tmuxWindowId
        if appState.uiState.selectedWorktreeId != worktree.id {
            appState.uiState.selectedWorktreeId = worktree.id
        }
        if appState.uiState.selectedProjectId != worktree.projectId {
            appState.uiState.selectedProjectId = worktree.projectId
        }

        for i in appState.runtimePanes.indices where appState.runtimePanes[i].tmuxWindowId == window.tmuxWindowId {
            appState.runtimePanes[i].isActive = appState.runtimePanes[i].tmuxPaneId == paneId
        }
        if let windowIndex = appState.runtimeWindows.firstIndex(where: { $0.tmuxWindowId == window.tmuxWindowId }) {
            appState.runtimeWindows[windowIndex].activePaneId = paneId
        }

        let tmux = tmuxBackend(for: worktree)
        let rawWindowId = rawWindowId(from: window)
        Task {
            try? await tmux.selectWindow(sessionId: sessionName, windowId: rawWindowId)
            try? await tmux.selectPane(sessionId: sessionName, paneId: paneId)
        }

        onTerminalSwitch?(sessionName, worktree.path, location(for: worktree))
        clearUnread(windowId: rawWindowId, worktree: worktree)
        fireHook(event: .onWindowFocus, worktreeId: worktree.id, windowName: window.title)
        saveUIState()
    }

    /// Clear unread output state for a window and recompute aggregates.
    private func clearUnread(windowId: String, worktree: Worktree) {
        let sessions = sessionsForEndpoint(of: worktree)
        // Update the last-seen timestamp in the tracker
        if let sessionName = worktree.tmuxSessionName,
           let activity = unreadTracker.currentActivity(
               sessionName: sessionName,
               windowId: windowId,
               in: sessions
           ) {
            unreadTracker.markSeen(worktreeId: worktree.id, windowId: windowId, activity: activity)
        }

        // Reset hasUnreadOutput on the RuntimeWindow
        if let index = appState.runtimeWindows.firstIndex(where: {
            $0.worktreeId == worktree.id && rawWindowId(from: $0) == windowId
        }) {
            appState.runtimeWindows[index].hasUnreadOutput = false
            appState.runtimeWindows[index].badge = StatusAggregator.windowBadge(hasUnreadOutput: false)
        }

        // Recompute worktree unread count and project aggregates
        updateUnreadCounts()
        updateAggregatedBadges()
        updateDockBadge()
    }

    // MARK: - Update Project

    /// Update a project's mutable fields (name, iconName) and persist.
    func updateProject(_ project: Project) {
        guard let idx = appState.projects.firstIndex(where: { $0.id == project.id }) else { return }
        appState.projects[idx] = project
        try? projectRepo.save(project)
    }

    /// Reorder projects to match the given ID sequence and persist.
    func reorderProjects(_ orderedIds: [UUID]) {
        let lookup = Dictionary(uniqueKeysWithValues: appState.projects.map { ($0.id, $0) })
        appState.projects = orderedIds.compactMap { lookup[$0] }
        try? projectRepo.reorder(ids: orderedIds)
    }

    // MARK: - Add Project

    /// Add a new project from a directory path. Creates Project, default Worktree,
    /// and tmux session. Returns the new project.
    /// Best effort: if path is a git repo, resolve gitCommonDir and branch.
    /// Non-git paths are allowed and still create a managed tmux session.
    @discardableResult
    func addProject(path: String, location: WorkspaceLocation = .local) async throws -> Project {
        let name = (path as NSString).lastPathComponent
        let git = gitBackend(for: location)
        let tmux = tmuxBackend(for: location)

        // Best effort git detection
        let isRepo = try await git.isGitRepo(path: path)
        var commonDir = path
        var detectedBranch: String?
        if isRepo {
            commonDir = try await git.gitCommonDir(path: path)
            // Detect the actual current branch
            let gitStatus = try? await git.status(worktreePath: path)
            detectedBranch = gitStatus?.branch ?? "main"
        }

        // For non-git dirs, use the folder name as worktree name
        let worktreeName = detectedBranch ?? name

        // Create project
        let project = Project(
            name: name,
            repoRootPath: path,
            gitCommonDir: commonDir,
            lastActiveAt: Date(),
            location: location
        )
        try projectRepo.save(project)

        // Create default worktree
        let sessionName = SessionNaming.sessionName(projectShortName: project.shortName, worktree: worktreeName)
        let worktree = Worktree(
            projectId: project.id,
            name: worktreeName,
            path: path,
            branch: detectedBranch,
            isMainWorktree: true,
            tmuxSessionName: sessionName,
            status: .active,
            location: location
        )
        try worktreeRepo.save(worktree)

        // Create tmux session
        Task {
            _ = try? await tmux.createSession(
                name: sessionName,
                cwd: path,
                environment: [
                    "MORI_PROJECT": project.name,
                    "MORI_WORKTREE": worktree.name,
                    "MORI_SESSION_NAME": sessionName,
                ]
            )
            await onSessionCreated?(tmux)
            await tmux.refreshNow()
        }

        // Refresh state
        try loadAll()

        // Pull in any worktrees/clones that already exist on disk for this
        // project, so a freshly added project shows all of its branches, not just
        // the root. Self-gates: git-worktree discovery needs a repo, clone/plain
        // discovery runs for any local project.
        _ = try? await importExistingWorktrees(projectId: project.id)

        // Select the new project
        selectProject(project.id)

        return project
    }

    /// Scan the project's git repo for worktrees that exist on disk but aren't
    /// tracked yet, and import them into the workspace. Returns the count imported.
    ///
    /// Idempotent: already-tracked paths (including the main worktree) and bare
    /// entries are skipped, so re-running only picks up newly created worktrees.
    @discardableResult
    func importExistingWorktrees(projectId: UUID) async throws -> Int {
        guard let project = appState.projects.first(where: { $0.id == projectId }) else {
            throw WorkspaceError.projectNotFound
        }
        let projectLocation = location(for: project)
        let git = gitBackend(for: projectLocation)
        let isRepo = try await git.isGitRepo(path: project.repoRootPath)
        let isLocal: Bool = { if case .local = projectLocation { return true }; return false }()

        // Everything already tracked, or explicitly dismissed by the user, must
        // not be re-imported. Paths imported earlier in this run are merged in as
        // we go so the two discovery passes don't double-import.
        var knownPaths = Set(
            appState.worktrees
                .filter { $0.projectId == projectId }
                .map { Self.normalizeWorktreePath($0.path) }
        )
        for dismissed in project.dismissedWorktreePaths ?? [] {
            knownPaths.insert(Self.normalizeWorktreePath(dismissed))
        }

        var imported: [Worktree] = []

        func register(
            path: String,
            branch: String?,
            headSHA: String?,
            isDetached: Bool,
            kind: WorktreeKind
        ) {
            let name = branch ?? (path as NSString).lastPathComponent
            let sessionName = SessionNaming.sessionName(projectShortName: project.shortName, worktree: name)
            let worktree = Worktree(
                projectId: projectId,
                name: name,
                path: path,
                branch: branch,
                headSHA: headSHA,
                isMainWorktree: false,
                isDetached: isDetached,
                tmuxSessionName: sessionName,
                status: .active,
                location: projectLocation,
                kind: kind
            )
            try? worktreeRepo.save(worktree)
            imported.append(worktree)
            // No tmux session here: a bulk import (discovery can find dozens of
            // directories) must not spawn a login shell per row. The session is
            // created lazily by ensureTmuxSession() when the row is selected.
        }

        // Pass 1: registered git worktrees (works local + remote).
        if isRepo {
            let infos = try await git.listWorktrees(repoPath: project.repoRootPath)
            for info in infos where !info.isBare {
                let norm = Self.normalizeWorktreePath(info.path)
                guard knownPaths.insert(norm).inserted else { continue }
                register(
                    path: info.path,
                    branch: info.branchName,
                    headSHA: info.head,
                    isDetached: info.isDetached,
                    kind: .gitWorktree
                )
            }
        }

        // Pass 2: COW clones / plain dirs under the discovery directory (local only).
        if isLocal {
            let baseDir = ToolSettings.load().resolvedWorktreeBaseDir()
            let projectSlug = SessionNaming.slugify(project.name)
            let discoveryDir = (baseDir as NSString).appendingPathComponent(projectSlug)
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: discoveryDir)) ?? []
            for entry in entries {
                let fullPath = (discoveryDir as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir),
                      isDir.boolValue else { continue }
                let norm = Self.normalizeWorktreePath(fullPath)
                guard knownPaths.insert(norm).inserted else { continue }

                switch CowCloner.classify(path: fullPath) {
                case .fullRepo:
                    let branch = try? await git.status(worktreePath: fullPath).branch
                    register(
                        path: fullPath,
                        branch: branch,
                        headSHA: nil,
                        isDetached: false,
                        kind: .cowClone
                    )
                case .plainDirectory:
                    register(
                        path: fullPath,
                        branch: nil,
                        headSHA: nil,
                        isDetached: false,
                        kind: .plainDirectory
                    )
                case .linkedWorktree:
                    // A registered worktree would have been caught by pass 1; an
                    // unregistered one is an orphan we don't manage — skip it.
                    continue
                }
            }
        }

        appState.worktrees.append(contentsOf: imported)
        return imported.count
    }

    /// Best-effort background discovery of workspaces created outside Mori
    /// (e.g. COW clones on disk) for every local project. Called at launch;
    /// swallows errors and shows no UI.
    func autoImportExistingWorkspaces() async {
        var didImport = false
        for project in appState.projects {
            guard case .local = location(for: project) else { continue }
            if let count = try? await importExistingWorktrees(projectId: project.id), count > 0 {
                didImport = true
            }
        }
        if didImport {
            await refreshRuntimeState()
        }
    }

    /// Normalize a worktree path for set membership: expand `~`, collapse `..`,
    /// and drop a trailing slash so DB and `git worktree list` paths compare equal.
    private static func normalizeWorktreePath(_ path: String) -> String {
        var normalized = (path as NSString).standardizingPath
        if normalized.count > 1, normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }

    @discardableResult
    func addRemoteProject(
        host: String,
        path: String,
        user: String? = nil,
        port: Int? = nil,
        authMethod: SSHAuthMethod = .publicKey,
        password: String? = nil
    ) async throws -> Project {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { throw WorkspaceError.remoteHostEmpty }
        guard !trimmedPath.isEmpty else { throw WorkspaceError.remotePathEmpty }
        if authMethod == .password, (password?.isEmpty ?? true) {
            throw WorkspaceError.remotePasswordEmpty
        }

        let sshLocation = SSHWorkspaceLocation(
            host: trimmedHost,
            user: user,
            port: port,
            authMethod: authMethod
        )
        if authMethod == .password {
            try await SSHBootstrapper.bootstrapPasswordSession(
                ssh: sshLocation,
                password: password
            )
            do {
                try SSHCredentialStore.savePassword(password ?? "", for: sshLocation)
            } catch {
                throw WorkspaceError.remotePasswordPersistFailed(error.localizedDescription)
            }
        }

        let location = WorkspaceLocation.ssh(
            sshLocation
        )
        let tmux = tmuxBackend(for: location)
        guard await tmux.isAvailable() else {
            throw WorkspaceError.remoteTmuxUnavailable(trimmedHost)
        }

        return try await addProject(
            path: trimmedPath,
            location: location
        )
    }

    /// List branches for a project using the correct backend for its location.
    /// `repoPathHint` is kept for UI callsites already passing repo path; the
    /// persisted project path remains the source of truth.
    func listBranches(projectId: UUID, repoPathHint: String? = nil) async throws -> [GitBranchInfo] {
        guard let project = appState.projects.first(where: { $0.id == projectId }) else {
            throw WorkspaceError.projectNotFound
        }
        let git = gitBackend(for: location(for: project))
        let repoPath = project.repoRootPath.isEmpty ? (repoPathHint ?? "") : project.repoRootPath
        return try await git.listBranches(repoPath: repoPath)
    }

    /// Prefetch open issues + PRs for the creation panel's `#` picker. Local
    /// projects only — `gh` is a local-only tool, so remote/SSH projects (and a
    /// missing gh) return an empty list, which keeps the panel's GitHub mode inert.
    func fetchGitHubWorkItems(projectId: UUID, repoPath: String) async -> [GitHubWorkItem] {
        guard let project = appState.projects.first(where: { $0.id == projectId }),
              case .local = location(for: project) else {
            return []
        }
        let dir = project.repoRootPath.isEmpty ? repoPath : project.repoRootPath
        guard !dir.isEmpty else { return [] }
        async let issues = gitHubBackend.issues(directory: dir)
        async let prs = gitHubBackend.openPullRequests(directory: dir)
        return await issues + prs
    }

    /// Update authentication settings for an existing remote project.
    /// Supports switching between public key and password auth without re-adding the project.
    func updateRemoteAuth(
        projectId: UUID,
        authMethod: SSHAuthMethod,
        password: String? = nil
    ) async throws {
        guard let projectIndex = appState.projects.firstIndex(where: { $0.id == projectId }) else {
            throw WorkspaceError.projectNotFound
        }
        let project = appState.projects[projectIndex]
        guard case .ssh(let currentSSH) = location(for: project) else {
            throw WorkspaceError.projectNotRemote
        }

        if authMethod == .password, (password?.isEmpty ?? true) {
            throw WorkspaceError.remotePasswordEmpty
        }

        var updatedSSH = currentSSH
        updatedSSH.authMethod = authMethod

        // Prime/validate credentials before applying model changes.
        if authMethod == .password {
            try await SSHBootstrapper.bootstrapPasswordSession(
                ssh: updatedSSH,
                password: password
            )
            do {
                try SSHCredentialStore.savePassword(password ?? "", for: updatedSSH)
            } catch {
                throw WorkspaceError.remotePasswordPersistFailed(error.localizedDescription)
            }
        }

        // Invalidate both old and new backend cache entries so future operations
        // pick up fresh auth options/password providers.
        invalidateRemoteBackends(for: currentSSH)
        invalidateRemoteBackends(for: updatedSSH)

        let updatedLocation = WorkspaceLocation.ssh(updatedSSH)
        let updatedTmux = tmuxBackend(for: updatedLocation)
        guard await updatedTmux.isAvailable() else {
            throw WorkspaceError.remoteTmuxUnavailable(updatedSSH.target)
        }

        if authMethod == .publicKey {
            SSHCredentialStore.deletePassword(for: currentSSH)
        }

        // Persist project location
        appState.projects[projectIndex].location = updatedLocation
        try projectRepo.save(appState.projects[projectIndex])

        // Persist all worktrees under this project to keep endpoint auth consistent.
        for i in appState.worktrees.indices where appState.worktrees[i].projectId == projectId {
            appState.worktrees[i].location = updatedLocation
            try worktreeRepo.save(appState.worktrees[i])
        }

        // Reconnect selected worktree if it belongs to this project so terminal
        // immediately uses the updated credentials.
        if let selected = selectedWorktree, selected.projectId == projectId {
            _ = await reconnectCurrentSession()
        }
    }

    /// List active tmux session names for a remote project.
    /// Returns an empty list for local projects or on scan failures.
    func listRemoteSessionNames(projectId: UUID) async -> [String] {
        guard let project = appState.projects.first(where: { $0.id == projectId }) else {
            return []
        }
        let location = location(for: project)
        guard case .ssh = location else { return [] }

        let tmux = tmuxBackend(for: location)
        let names = (try? await tmux.listSessionNames()) ?? []
        return names.sorted()
    }

    /// Attach the project's main worktree to an existing remote tmux session.
    func attachMainWorktreeToRemoteSession(
        projectId: UUID,
        sessionName: String
    ) async throws {
        guard let project = appState.projects.first(where: { $0.id == projectId }) else {
            throw WorkspaceError.projectNotFound
        }
        let location = location(for: project)
        guard case .ssh = location else {
            throw WorkspaceError.projectNotRemote
        }

        let trimmed = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw WorkspaceError.remoteSessionNameEmpty
        }

        let tmux = tmuxBackend(for: location)
        let sessions = try await tmux.scanAll()
        guard sessions.contains(where: { $0.name == trimmed }) else {
            throw WorkspaceError.remoteSessionNotFound(trimmed)
        }

        guard let worktreeIndex = appState.worktrees.firstIndex(where: {
            $0.projectId == projectId && $0.isMainWorktree
        }) ?? appState.worktrees.firstIndex(where: { $0.projectId == projectId }) else {
            throw WorkspaceError.projectNotFound
        }

        let endpoint = endpointKey(for: appState.worktrees[worktreeIndex])
        let isAttachedElsewhere = appState.worktrees.contains(where: { worktree in
            guard worktree.id != appState.worktrees[worktreeIndex].id else { return false }
            guard let existing = worktree.tmuxSessionName else { return false }
            return existing == trimmed && endpointKey(for: worktree) == endpoint
        })
        if isAttachedElsewhere {
            throw WorkspaceError.remoteSessionAlreadyAttached(trimmed)
        }

        appState.worktrees[worktreeIndex].tmuxSessionName = trimmed
        try worktreeRepo.save(appState.worktrees[worktreeIndex])

        let worktree = appState.worktrees[worktreeIndex]
        if appState.uiState.selectedProjectId != projectId {
            appState.uiState.selectedProjectId = projectId
        }
        selectWorktree(worktree.id)
    }

    // MARK: - Create Worktree

    /// Create a new worktree for a project: git worktree add, DB save, tmux session, template apply.
    /// Partial failure: if git succeeds but tmux fails, worktree is still saved to DB.
    /// If git fails, no DB write occurs.
    ///
    /// - Parameters:
    ///   - projectId: The project to create the worktree under.
    ///   - branchName: The branch name (existing or new).
    ///   - createBranch: Whether to create a new branch (`true`) or use an existing one (`false`).
    ///   - baseBranch: Base branch for new branch creation (only used when `createBranch` is `true`).
    ///   - origin: Where the request came from — a plain branch, a GitHub issue,
    ///     or a GitHub PR (which is checked out onto its head branch).
    @discardableResult
    func createWorktree(
        projectId: UUID,
        branchName: String,
        createBranch: Bool = true,
        baseBranch: String? = nil,
        origin: CreationOrigin = .branch
    ) async throws -> Worktree {
        guard let project = appState.projects.first(where: { $0.id == projectId }) else {
            throw WorkspaceError.projectNotFound
        }

        // A PR origin works ON the PR's head branch rather than creating a new
        // one. The panel carries the head ref from the prefetched `gh pr list`;
        // the record's branch matches it so the PR badge/status pipeline lights
        // up. A missing head ref (rare gh API gap) can't be materialized.
        var effectiveBranch = branchName
        var effectiveCreateBranch = createBranch
        var pullRequestNumber: Int?
        if case .pullRequest(let number, let headRef) = origin {
            guard !headRef.isEmpty else {
                throw WorkspaceError.pullRequestUnavailable(number)
            }
            effectiveBranch = headRef
            effectiveCreateBranch = false
            pullRequestNumber = number
        }

        // Validate inputs
        let trimmed = effectiveBranch.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw WorkspaceError.branchNameEmpty
        }

        // Reject branch names with spaces or characters git doesn't allow
        let invalidChars = CharacterSet(charactersIn: " ~^:?*[\\")
        if trimmed.unicodeScalars.contains(where: { invalidChars.contains($0) }) {
            throw WorkspaceError.branchNameInvalid(trimmed)
        }

        let projectLocation = location(for: project)
        let git = gitBackend(for: projectLocation)
        let tmux = tmuxBackend(for: projectLocation)

        let projectSlug = SessionNaming.slugify(project.name)
        let branchSlug = SessionNaming.slugify(trimmed)

        // Compute worktree path.
        // Local: <worktree base dir>/{project-slug}/{branch-slug} (defaults to ~/.mori)
        // Remote SSH: <repo parent>/.mori/{project-slug}/{branch-slug}
        let projectDir: String
        switch projectLocation {
        case .local:
            let moriDir = ToolSettings.load().resolvedWorktreeBaseDir()
            projectDir = (moriDir as NSString).appendingPathComponent(projectSlug)
        case .ssh:
            let parentDir = (project.repoRootPath as NSString).deletingLastPathComponent
            let moriDir = (parentDir as NSString).appendingPathComponent(".mori")
            projectDir = (moriDir as NSString).appendingPathComponent(projectSlug)
        }
        let worktreePath = (projectDir as NSString).appendingPathComponent(branchSlug)

        // Step 1: Prepare workspace path.
        // Ensure the parent container exists before any git worktree operation.
        // This is required for first-time remote usage where `<parent>/.mori/<project>`
        // has not been created yet.
        try await git.ensureDirectory(path: projectDir)

        let isGitRepo = try await git.isGitRepo(path: project.repoRootPath)
        let preferCow = ToolSettings.load().preferCowClones

        // Optimistic placeholder: the row appears in the sidebar immediately
        // with a "Creating…" status while materialization runs. In-memory only —
        // it is persisted after promotion to .active, so a crash mid-create
        // can't leave a stale record pointing at a half-built directory.
        let sessionName = SessionNaming.sessionName(projectShortName: project.shortName, worktree: trimmed)
        var worktree = Worktree(
            projectId: projectId,
            name: trimmed,
            path: worktreePath,
            branch: trimmed,
            isMainWorktree: false,
            tmuxSessionName: sessionName,
            status: .creating,
            location: projectLocation
        )
        appState.worktrees.append(worktree)

        // Materialize the workspace on disk and record how it was made.
        let kind: WorktreeKind
        do {
            if case .local = projectLocation, preferCow {
                kind = try await materializeLocalWorkspace(
                    repoRootPath: project.repoRootPath,
                    worktreePath: worktreePath,
                    branch: trimmed,
                    createBranch: effectiveCreateBranch,
                    baseBranch: baseBranch,
                    isGitRepo: isGitRepo,
                    git: git,
                    pullRequestNumber: pullRequestNumber
                )
            } else if isGitRepo {
                // SSH projects, or local with clones disabled: existing git worktree path.
                try await addGitWorktreeWithRetry(
                    git: git,
                    repoPath: project.repoRootPath,
                    path: worktreePath,
                    branch: trimmed,
                    createBranch: effectiveCreateBranch,
                    baseBranch: baseBranch,
                    pullRequestNumber: pullRequestNumber
                )
                kind = .gitWorktree
            } else {
                // Non-git plain-copy path can't check out a PR.
                if pullRequestNumber != nil {
                    throw WorkspaceError.pullRequestRequiresGitRepo
                }
                try await git.ensureDirectory(path: worktreePath)
                kind = .plainDirectory
            }
        } catch {
            // Roll back the placeholder so the sidebar doesn't show a ghost row.
            appState.worktrees.removeAll { $0.id == worktree.id }
            throw error
        }

        // A previously-removed workspace at this exact path is being recreated;
        // clear the dismissal so auto-discovery treats it as tracked again.
        clearDismissedWorkspacePath(projectId: projectId, path: worktreePath)

        // Step 2: Promote the placeholder and persist.
        worktree.status = .active
        worktree.kind = kind
        if let idx = appState.worktrees.firstIndex(where: { $0.id == worktree.id }) {
            appState.worktrees[idx] = worktree
        }
        try worktreeRepo.save(worktree)

        // Step 3: Create tmux session (partial failure tolerant)
        do {
            _ = try await tmux.createSession(
                name: sessionName,
                cwd: worktreePath,
                environment: moriPaneEnvironment(for: worktree)
            )
            await onSessionCreated?(tmux)
        } catch {
            // tmux failure is non-fatal — session will be created on next select
        }

        // Step 4: Select (the row is already in appState from the placeholder)
        selectWorktree(worktree.id)

        // Fire onWorktreeCreate hook
        fireHook(event: .onWorktreeCreate, worktreeId: worktree.id)

        return worktree
    }

    /// Create a local workspace by APFS copy-on-write clone, falling back to
    /// `git worktree add` (git repos) or a plain recursive copy (non-git) when
    /// cloning isn't possible (cross-volume / non-APFS). Returns the resulting
    /// `WorktreeKind`. Runs the blocking clone off the main actor.
    private func materializeLocalWorkspace(
        repoRootPath: String,
        worktreePath: String,
        branch: String,
        createBranch: Bool,
        baseBranch: String?,
        isGitRepo: Bool,
        git: GitBackend,
        pullRequestNumber: Int?
    ) async throws -> WorktreeKind {
        // A PR checkout needs a git repo; reject before cloning so a non-git
        // project never silently produces a plain copy with no PR checked out.
        // (Thrown here, outside the do/catch, so the plain-copy fallback can't
        // swallow it.)
        if pullRequestNumber != nil, !isGitRepo {
            throw WorkspaceError.pullRequestRequiresGitRepo
        }
        do {
            try await Task.detached(priority: .userInitiated) {
                try CowCloner.clone(from: repoRootPath, to: worktreePath)
            }.value

            switch CowCloner.classify(path: worktreePath) {
            case .fullRepo:
                if let pullRequestNumber {
                    // PR flow: reset the clone (drop inherited dirty tracked state
                    // and stale worktree links) then let gh check out the PR head
                    // branch, replacing gitFixup's branch checkout.
                    try await CowCloner.resetForPullRequestCheckout(clonePath: worktreePath)
                    try await gitHubBackend.checkoutPullRequest(number: pullRequestNumber, directory: worktreePath)
                } else {
                    try await CowCloner.gitFixup(
                        clonePath: worktreePath,
                        branch: branch,
                        createBranch: createBranch,
                        baseBranch: baseBranch
                    )
                }
                return .cowClone
            case .plainDirectory:
                // Non-git project cloned successfully — a deliberate feature.
                return .plainDirectory
            case .linkedWorktree:
                // Source is itself a linked worktree; a clone of it is untrustworthy.
                // Drop it and fall back to the git worktree path below.
                try? FileManager.default.removeItem(atPath: worktreePath)
                throw CowCloner.CowCloneError.cloneUnsupported(
                    errno: 0,
                    message: "source is a linked git worktree"
                )
            }
        } catch {
            // Clone failed or was unsuitable — clean up any partial dest and fall back.
            try? FileManager.default.removeItem(atPath: worktreePath)
            if isGitRepo {
                try await addGitWorktreeWithRetry(
                    git: git,
                    repoPath: repoRootPath,
                    path: worktreePath,
                    branch: branch,
                    createBranch: createBranch,
                    baseBranch: baseBranch,
                    pullRequestNumber: pullRequestNumber
                )
                return .gitWorktree
            } else {
                // Non-git fallback: a plain recursive copy preserves the project
                // contents (unlike the previous empty-directory behavior). Off the
                // main actor — a physical copy of a large tree can take a while.
                try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.copyItem(atPath: repoRootPath, toPath: worktreePath)
                }.value
                return .plainDirectory
            }
        }
    }

    /// `git worktree add` with the "branch already exists" retry preserved.
    /// For a PR origin, adds a detached worktree (on `baseBranch` when given)
    /// and lets `gh pr checkout` create/switch to the PR's head branch inside it.
    private func addGitWorktreeWithRetry(
        git: GitBackend,
        repoPath: String,
        path: String,
        branch: String,
        createBranch: Bool,
        baseBranch: String?,
        pullRequestNumber: Int? = nil
    ) async throws {
        if let pullRequestNumber {
            try await git.addWorktreeDetached(repoPath: repoPath, path: path, ref: baseBranch)
            try await gitHubBackend.checkoutPullRequest(number: pullRequestNumber, directory: path)
            return
        }
        do {
            try await git.addWorktree(
                repoPath: repoPath,
                path: path,
                branch: branch,
                createBranch: createBranch,
                baseBranch: baseBranch
            )
        } catch let gitError as GitError where createBranch && isBranchAlreadyExistsError(gitError, branch: branch) {
            // User typed an existing branch but branch metadata was stale/unavailable.
            // Retry as "use existing branch" to keep workspace creation smooth.
            try await git.addWorktree(
                repoPath: repoPath,
                path: path,
                branch: branch,
                createBranch: false,
                baseBranch: nil
            )
        }
    }

    private func isBranchAlreadyExistsError(_ error: GitError, branch: String) -> Bool {
        guard case .executionFailed(_, _, let stderr) = error else { return false }
        let message = stderr.lowercased()
        if message.contains("already exists") && message.contains("branch") {
            return true
        }
        // Handle outputs that include branch name but omit explicit "branch" token.
        return message.contains("already exists") && message.contains(branch.lowercased())
    }

    /// Handle create worktree from the creation panel — extracts parameters from the
    /// request, calls createWorktree, and shows error alerts on failure.
    func handleCreateWorktreeFromPanel(_ request: WorktreeCreationRequest) async {
        let trimmed = request.branchName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            showErrorAlert(title: .localized("Invalid Branch Name"), message: WorkspaceError.branchNameEmpty.localizedDescription)
            return
        }

        guard let projectId = appState.uiState.selectedProjectId else {
            showErrorAlert(title: .localized("No Project Selected"), message: .localized("Please select a project first."))
            return
        }

        do {
            _ = try await createWorktree(
                projectId: projectId,
                branchName: trimmed,
                createBranch: request.isNewBranch,
                baseBranch: request.baseBranch,
                origin: request.origin
            )
            await refreshRuntimeState()
        } catch {
            showErrorAlert(title: .localized("Failed to Create Worktree"), message: error.localizedDescription)
        }
    }

    /// Show a user-facing error alert.
    private func showErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: .localized("OK"))
        alert.runModal()
    }

    // MARK: - Remove Worktree

    /// Remove a worktree with confirmation dialog.
    /// "Remove from Mori" = soft delete (mark unavailable).
    /// "Remove from Mori and delete files" = soft delete + git worktree remove.
    func removeWorktree(worktreeId: UUID) async {
        guard let index = appState.worktrees.firstIndex(where: { $0.id == worktreeId }) else { return }
        let worktree = appState.worktrees[index]
        guard !worktree.status.isTransient else { return }

        // Don't allow removing the main worktree
        if worktree.isMainWorktree {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = .localized("Cannot remove main worktree")
            alert.informativeText = .localized("The main worktree is tied to the project's root directory and cannot be removed.")
            alert.addButton(withTitle: .localized("OK"))
            alert.runModal()
            return
        }

        // Decide, from on-disk truth, how "Delete Files" would remove this
        // workspace, and whether we must warn about irrecoverable local commits.
        let isLocal: Bool = { if case .local = location(for: worktree) { return true }; return false }()
        let onDisk = isLocal ? CowCloner.classify(path: worktree.path) : .linkedWorktree
        // A COW clone owns its branch/commits; a linked worktree's branch lives
        // in the main repo, so only clones risk data loss on file deletion.
        let isCowClone = isLocal && onDisk == .fullRepo

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = .localized("Remove worktree \"\(worktree.name)\"?")
        if isCowClone, let (ahead, dirty) = await unpushedWork(for: worktree), ahead > 0 || dirty {
            alert.informativeText = String(
                format: .localized("This workspace is a copy-on-write clone at %@.\n\nBranch \"%@\" and its unpushed work (%d commit(s) ahead, %@) exist only in this clone. Deleting the files will permanently lose them."),
                worktree.path,
                worktree.branch ?? worktree.name,
                ahead,
                dirty ? String.localized("uncommitted changes present") : String.localized("no uncommitted changes")
            )
        } else {
            alert.informativeText = .localized("This worktree is at \(worktree.path)")
        }
        alert.addButton(withTitle: .localized("Remove from Mori"))
        alert.addButton(withTitle: .localized("Remove from Mori and Delete Files"))
        alert.addButton(withTitle: .localized("Cancel"))

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            // Re-find by id: the awaits and modal above suspend the main actor,
            // and a background deletion finishing meanwhile shifts the array —
            // the entry index would remove the wrong row or trap.
            guard let idx = appState.worktrees.firstIndex(where: { $0.id == worktree.id }),
                  !appState.worktrees[idx].status.isTransient else { return }
            // Fire onWorktreeClose hook before cleanup
            fireHook(event: .onWorktreeClose, worktreeId: worktree.id)
            // Soft delete — remove from Mori but leave files on disk.
            recordDismissedWorkspacePath(projectId: worktree.projectId, path: worktree.path)
            softDeleteWorktree(at: idx)

        case .alertSecondButtonReturn:
            // Delete files. Clones/plain dirs are removed directly (they are not
            // registered git worktrees); linked worktrees use `git worktree remove`.
            let useDirectDelete = isLocal && (onDisk == .fullRepo || onDisk == .plainDirectory)
            if useDirectDelete, let reason = unsafeDirectoryDeletionReason(worktree: worktree) {
                // Guardrails failed — abort entirely (do not remove from Mori).
                showErrorAlert(
                    title: .localized("Cannot delete workspace files"),
                    message: reason
                )
                return
            }
            startWorktreeDeletion(worktreeId: worktree.id, force: false)

        default:
            // Cancel — do nothing
            break
        }
    }

    /// Delete a workspace's files in the background while its sidebar row shows
    /// "Deleting…". The row is deselected up front (its session dies first) but
    /// only removed from state once the files are gone, so a failure can restore
    /// the row and surface an error — with a Force Delete retry for linked
    /// worktrees that git refuses to remove (uncommitted changes, locks).
    private func startWorktreeDeletion(worktreeId: UUID, force: Bool) {
        guard let index = appState.worktrees.firstIndex(where: { $0.id == worktreeId }),
              appState.worktrees[index].status != .deleting else { return }
        let worktree = appState.worktrees[index]
        let previousStatus = worktree.status

        appState.worktrees[index].status = .deleting
        deselectWorktree(worktree.id)

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.performWorktreeFileDeletion(worktree, force: force)
                // Fire only once the deletion is irreversible: a failed attempt
                // restores the row, and close hooks must not see false or
                // duplicate (Force Delete retry) close events.
                self.fireHook(event: .onWorktreeClose, worktreeId: worktree.id)
                self.recordDismissedWorkspacePath(projectId: worktree.projectId, path: worktree.path)
                if let idx = self.appState.worktrees.firstIndex(where: { $0.id == worktree.id }) {
                    self.softDeleteWorktree(at: idx)
                }
            } catch {
                if let idx = self.appState.worktrees.firstIndex(where: { $0.id == worktree.id }) {
                    self.appState.worktrees[idx].status = previousStatus
                }
                // Force only changes `git worktree remove`; a direct FileManager
                // failure (permissions, mounts) would fail identically again.
                let canForce = !force && ((try? self.requiresDirectDeletion(worktree)) == false)
                self.presentDeletionFailure(worktreeId: worktree.id, message: error.localizedDescription, canForce: canForce)
            }
        }
    }

    private func presentDeletionFailure(worktreeId: UUID, message: String, canForce: Bool) {
        guard canForce else {
            showErrorAlert(title: .localized("Failed to delete worktree files"), message: message)
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = .localized("Failed to delete worktree files")
        alert.informativeText = message + "\n\n" + .localized("Force deleting discards uncommitted changes and untracked files in this worktree.")
        alert.addButton(withTitle: .localized("Force Delete"))
        alert.addButton(withTitle: .localized("Cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            startWorktreeDeletion(worktreeId: worktreeId, force: true)
        }
    }

    /// True when the workspace's files must be removed directly (COW clone or
    /// plain directory — not a registered git worktree); false for linked
    /// worktrees, which go through `git worktree remove`. Throws when direct
    /// deletion would be unsafe (path outside the managed workspace dir).
    private func requiresDirectDeletion(_ worktree: Worktree) throws -> Bool {
        let isLocal: Bool = { if case .local = location(for: worktree) { return true }; return false }()
        let onDisk = isLocal ? CowCloner.classify(path: worktree.path) : .linkedWorktree
        let useDirect = isLocal && (onDisk == .fullRepo || onDisk == .plainDirectory)
        if useDirect, let reason = unsafeDirectoryDeletionReason(worktree: worktree) {
            throw WorkspaceError.unsafeWorkspaceDeletion(reason)
        }
        return useDirect
    }

    /// Kill the session and remove the files. Shared by the UI and IPC deletion
    /// paths; callers own state transitions (status, dismissal, soft delete).
    private func performWorktreeFileDeletion(_ worktree: Worktree, force: Bool) async throws {
        let useDirectDelete = try requiresDirectDeletion(worktree)

        // Kill the session first so its processes stop holding (and writing) the tree.
        if let sessionName = worktree.tmuxSessionName {
            try? await tmuxBackend(for: worktree).killSession(id: sessionName)
        }

        if useDirectDelete {
            try await Self.removeDirectoryOffMain(atPath: worktree.path)
        } else if let project = appState.projects.first(where: { $0.id == worktree.projectId }) {
            let git = gitBackend(for: location(for: project))
            try await git.removeWorktree(repoPath: project.repoRootPath, path: worktree.path, force: force)
        }
    }

    /// `FileManager.removeItem` walks the whole tree synchronously — many
    /// seconds for a multi-GB clone — so it must not run on the main actor.
    private nonisolated static func removeDirectoryOffMain(atPath path: String) async throws {
        try await Task.detached(priority: .utility) {
            try FileManager.default.removeItem(atPath: path)
        }.value
    }

    /// Best-effort probe for work that would be permanently lost if a COW clone's
    /// files are deleted: commits ahead of upstream (or, lacking an upstream,
    /// ahead of the default/base branch) plus any uncommitted changes.
    /// Returns nil when git status can't be read.
    private func unpushedWork(for worktree: Worktree) async -> (ahead: Int, dirty: Bool)? {
        let git = gitBackend(for: worktree)
        guard let status = try? await git.status(worktreePath: worktree.path) else { return nil }
        let dirty = status.isDirty
        if status.upstream != nil {
            return (status.ahead, dirty)
        }
        // No upstream: count commits not reachable from a plausible base ref.
        for base in ["origin/HEAD", "main", "master"] {
            if let ahead = try? await git.commitsAhead(worktreePath: worktree.path, baseRef: base) {
                return (ahead, dirty)
            }
        }
        return (0, dirty)
    }

    /// Validate that a workspace path is safe to delete via `FileManager`.
    /// Returns a localized reason string when unsafe, nil when safe. All checks
    /// must pass: strictly under the worktree base dir, not the repo root, not
    /// the home directory, and not a suspiciously shallow path.
    private func unsafeDirectoryDeletionReason(worktree: Worktree) -> String? {
        let std = (worktree.path as NSString).standardizingPath
        let baseDir = (ToolSettings.load().resolvedWorktreeBaseDir() as NSString).standardizingPath
        let home = (NSHomeDirectory() as NSString).standardizingPath

        let genericUnsafe = String(
            format: .localized("Refusing to delete \"%@\": it is not inside the managed workspace directory."),
            std
        )

        guard std.hasPrefix(baseDir + "/") else { return genericUnsafe }
        if std == home { return genericUnsafe }
        if let project = appState.projects.first(where: { $0.id == worktree.projectId }),
           (project.repoRootPath as NSString).standardizingPath == std {
            return genericUnsafe
        }
        // Depth sanity: never "/" or a top-level directory.
        let components = std.split(separator: "/", omittingEmptySubsequences: true)
        if components.count < 2 { return genericUnsafe }
        return nil
    }

    /// Record that the user removed a workspace whose files may remain on disk,
    /// so auto-discovery won't resurrect it. Paths are normalized for comparison.
    private func recordDismissedWorkspacePath(projectId: UUID, path: String) {
        guard let idx = appState.projects.firstIndex(where: { $0.id == projectId }) else { return }
        let norm = Self.normalizeWorktreePath(path)
        var dismissed = appState.projects[idx].dismissedWorktreePaths ?? []
        guard !dismissed.contains(norm) else { return }
        dismissed.append(norm)
        appState.projects[idx].dismissedWorktreePaths = dismissed
        try? projectRepo.save(appState.projects[idx])
    }

    /// Undo a prior dismissal (e.g. the user recreates a workspace at that path).
    private func clearDismissedWorkspacePath(projectId: UUID, path: String) {
        guard let idx = appState.projects.firstIndex(where: { $0.id == projectId }) else { return }
        let norm = Self.normalizeWorktreePath(path)
        guard var dismissed = appState.projects[idx].dismissedWorktreePaths,
              dismissed.contains(norm) else { return }
        dismissed.removeAll { $0 == norm }
        appState.projects[idx].dismissedWorktreePaths = dismissed.isEmpty ? nil : dismissed
        try? projectRepo.save(appState.projects[idx])
    }

    /// Remove a project and all its worktrees with confirmation dialog.
    func removeProject(projectId: UUID) async {
        guard let project = appState.projects.first(where: { $0.id == projectId }) else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = .localized("Remove project \"\(project.name)\"?")
        alert.informativeText = .localized("This will remove the project and all its worktrees from Mori. Git repositories on disk will not be deleted.")
        alert.addButton(withTitle: .localized("Remove"))
        alert.addButton(withTitle: .localized("Cancel"))

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        // Collect worktrees belonging to this project
        let projectWorktrees = appState.worktrees.filter { $0.projectId == projectId }

        // Kill tmux sessions for all worktrees
        for worktree in projectWorktrees {
            if let sessionName = worktree.tmuxSessionName {
                try? await tmuxBackend(for: worktree).killSession(id: sessionName)
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
    /// Headless worktree deletion for IPC (no UI dialogs).
    /// Kills the tmux session, removes the git worktree, and soft-deletes from state.
    func deleteWorktree(worktreeId: UUID) async throws {
        guard let index = appState.worktrees.firstIndex(where: { $0.id == worktreeId }) else {
            throw WorkspaceError.worktreeNotFound
        }
        let worktree = appState.worktrees[index]

        if worktree.isMainWorktree {
            throw WorkspaceError.cannotDeleteMainWorktree
        }
        guard worktree.status != .deleting else { throw WorkspaceError.deletionInProgress }

        // Guardrails are checked before any side effect (tmux kill, status
        // flip) so a refusal leaves the workspace fully intact.
        _ = try requiresDirectDeletion(worktree)

        let previousStatus = worktree.status
        appState.worktrees[index].status = .deleting
        deselectWorktree(worktree.id)

        do {
            try await performWorktreeFileDeletion(worktree, force: false)
        } catch {
            if let idx = appState.worktrees.firstIndex(where: { $0.id == worktree.id }) {
                appState.worktrees[idx].status = previousStatus
            }
            throw error
        }

        // As in the UI path: only a completed deletion is a close event.
        fireHook(event: .onWorktreeClose, worktreeId: worktree.id)
        recordDismissedWorkspacePath(projectId: worktree.projectId, path: worktree.path)
        if let idx = appState.worktrees.firstIndex(where: { $0.id == worktree.id }) {
            softDeleteWorktree(at: idx)
        }
    }

    private func softDeleteWorktree(at index: Int) {
        let worktree = appState.worktrees[index]

        // Remove from state and database
        appState.worktrees.remove(at: index)
        try? worktreeRepo.delete(id: worktree.id)

        deselectWorktree(worktree.id)
    }

    /// If this worktree is selected, move selection to another active worktree
    /// (or clear it). Used both when a row disappears and when it enters the
    /// `.deleting` state, so the terminal never shows a dying session.
    private func deselectWorktree(_ worktreeId: UUID) {
        guard appState.uiState.selectedWorktreeId == worktreeId else { return }
        appState.uiState.selectedWorktreeId = nil
        appState.uiState.selectedWindowId = nil
        let active = appState.worktreesForSelectedProject.filter { $0.status == .active }
        if let first = active.first {
            selectWorktree(first.id)
        }
        saveUIState()
    }

    // MARK: - Tmux Integration

    /// Check the actual git branch for a worktree and update if it changed.
    private func refreshWorktreeBranch(worktreeId: UUID) async {
        guard let worktree = appState.worktrees.first(where: { $0.id == worktreeId }) else { return }

        let git = gitBackend(for: worktree)
        guard let gitStatus = try? await git.status(worktreePath: worktree.path),
              let branch = gitStatus.branch,
              branch != worktree.branch else { return }

        // Re-find by id: the array can shift during the await (a background
        // deletion completing), and the row may have turned transient.
        guard let index = appState.worktrees.firstIndex(where: { $0.id == worktreeId }),
              !appState.worktrees[index].status.isTransient else { return }
        appState.worktrees[index].branch = branch
        appState.worktrees[index].name = branch
        try? worktreeRepo.save(appState.worktrees[index])
    }

    /// Best-effort classification for missing tmux failures.
    private func isTmuxUnavailableError(_ error: any Error) -> Bool {
        guard let tmuxError = error as? TmuxError else { return false }
        switch tmuxError {
        case .binaryNotFound:
            return true
        case .executionFailed(_, let exitCode, let stderr):
            return exitCode == 127 && stderr.contains("tmux: command not found")
        default:
            return false
        }
    }

    private func tmuxUnavailableMessage(for worktree: Worktree) -> String {
        switch location(for: worktree) {
        case .local:
            return .localized("Mori requires tmux to manage terminal sessions. Please install tmux and relaunch the app.\n\nInstall via Homebrew:\n  brew install tmux\n\nOr via MacPorts:\n  sudo port install tmux")
        case .ssh(let ssh):
            return WorkspaceError.remoteTmuxUnavailable(ssh.target).localizedDescription
        }
    }

    private func showTmuxOperationError(
        title: String,
        error: any Error,
        worktree: Worktree
    ) {
        if isTmuxUnavailableError(error) {
            showErrorAlert(title: .localized("Terminal Error"), message: tmuxUnavailableMessage(for: worktree))
            return
        }
        showErrorAlert(title: title, message: error.localizedDescription)
    }

    /// Ensure a tmux session exists for the given worktree, creating one if needed.
    /// Returns false if session scan/create failed.
    @discardableResult
    private func ensureTmuxSession(for worktree: Worktree, showErrors: Bool = false) async -> Bool {
        guard let sessionName = worktree.tmuxSessionName else { return false }
        let tmux = tmuxBackend(for: worktree)

        let sessionNames: [String]
        do {
            sessionNames = try await tmux.listSessionNames()
        } catch {
            if showErrors {
                showTmuxOperationError(title: .localized("Terminal Error"), error: error, worktree: worktree)
            }
            return false
        }

        if !sessionNames.contains(sessionName) {
            do {
                _ = try await tmux.createSession(
                    name: sessionName,
                    cwd: worktree.path,
                    environment: moriPaneEnvironment(for: worktree)
                )
                await onSessionCreated?(tmux)
                return true
            } catch {
                if showErrors {
                    showTmuxOperationError(title: .localized("Terminal Error"), error: error, worktree: worktree)
                }
                return false
            }
        }

        // Keep at least one live window in the target session.
        let windowCount: Int
        do {
            windowCount = try await tmux.windowCount(sessionName: sessionName)
        } catch {
            if showErrors {
                showTmuxOperationError(title: .localized("Terminal Error"), error: error, worktree: worktree)
            }
            return false
        }
        if windowCount == 0 {
            do {
                _ = try await tmux.createWindow(
                    sessionId: sessionName,
                    name: nil,
                    cwd: worktree.path,
                    environment: moriPaneEnvironment(for: worktree)
                )
            } catch {
                if showErrors {
                    showTmuxOperationError(title: .localized("Terminal Error"), error: error, worktree: worktree)
                }
                return false
            }
        }
        return true
    }

    /// Refresh runtime windows/panes from tmux into AppState.
    /// Also re-runs agent detection immediately so ad-hoc refreshes don't wipe
    /// agent state until the next polling tick.
    func refreshRuntimeState() async {
        let sessionsByEndpoint = await scanSessionsByEndpoint()
        latestSessionsByEndpoint = sessionsByEndpoint

        // Build lookup of existing tags to preserve
        let previousTags: [String: WindowTag?] = Dictionary(
            appState.runtimeWindows.map { ($0.tmuxWindowId, $0.tag) },
            uniquingKeysWith: { first, _ in first }
        )

        var runtimeWindows: [RuntimeWindow] = []
        var seenWindowIDs = Set<String>()

        for worktree in appState.worktrees {
            guard let sessionName = worktree.tmuxSessionName else { continue }
            let endpointKey = endpointKey(for: worktree)
            let sessions = sessionsByEndpoint[endpointKey] ?? []
            guard let session = sessions.first(where: { $0.name == sessionName }) else { continue }

            for tmuxWindow in session.windows {
                let namespacedId = namespacedWindowId(rawWindowId: tmuxWindow.windowId, worktree: worktree)
                guard seenWindowIDs.insert(namespacedId).inserted else { continue }
                // Preserve existing tag or infer from window name
                let tag: WindowTag? = if let existing = previousTags[namespacedId] {
                    existing
                } else {
                    WindowTag.infer(from: tmuxWindow.name)
                }

                let rw = RuntimeWindow(
                    tmuxWindowId: namespacedId,
                    tmuxWindowRawId: tmuxWindow.windowId,
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
        await detectAgentStates(sessionsByEndpoint: sessionsByEndpoint)
        updateUnreadCounts()
        updateAggregatedBadges()
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

    /// Worktrees worth spawning git subprocesses for each tick: the selected
    /// one plus any whose tmux session is alive (per the previous tick's scan).
    /// Sessions exist only for workspaces the user actually opened, so an
    /// imported-but-untouched row costs nothing; its git fields keep their
    /// persisted values until it is selected.
    private func worktreesToPoll() -> [Worktree] {
        appState.worktrees.filter { worktree in
            if worktree.id == appState.uiState.selectedWorktreeId { return true }
            guard let sessionName = worktree.tmuxSessionName else { return false }
            let sessions = latestSessionsByEndpoint[endpointKey(for: worktree)] ?? []
            return sessions.contains { $0.name == sessionName }
        }
    }

    /// Perform a single coordinated poll: tmux scan + git status concurrently.
    func coordinatedPoll() async {
        // Run tmux scan and git status concurrently
        async let tmuxResult: [String: [TmuxSession]] = self.scanSessionsByEndpoint()
        async let gitResult: [UUID: WorktreeGitSnapshot] = {
            await self.gitStatusCoordinator.pollAll(
                worktrees: self.worktreesToPoll(),
                backendForWorktree: { worktree in
                    self.gitBackend(for: worktree)
                },
                baseRefForWorktree: { worktree in
                    self.baseRef(for: worktree)
                }
            )
        }()

        var sessionsByEndpoint = await tmuxResult
        let gitStatuses = await gitResult

        // Update runtime state from tmux
        if !sessionsByEndpoint.isEmpty {
            // Detect dead sessions and auto-recreate before updating state
            let recovered = await detectAndRecoverDeadSessions(sessionsByEndpoint: sessionsByEndpoint)
            if recovered {
                sessionsByEndpoint = await scanSessionsByEndpoint()
            }

            latestSessionsByEndpoint = sessionsByEndpoint

            // Detect unread activity before updating runtime state
            var unreadWindowKeys: Set<String> = []
            let selectedWindow = appState.runtimeWindows.first(where: {
                $0.tmuxWindowId == appState.uiState.selectedWindowId
            })
            for worktree in appState.worktrees {
                let endpointKey = endpointKey(for: worktree)
                let sessions = sessionsByEndpoint[endpointKey] ?? []
                let selectedRawWindowId: String? = if selectedWindow?.worktreeId == worktree.id {
                    selectedWindow.map(rawWindowId)
                } else {
                    nil
                }
                unreadWindowKeys.formUnion(
                    unreadTracker.processActivity(
                        sessions: sessions,
                        worktrees: [worktree],
                        selectedWindowId: selectedRawWindowId
                    )
                )
            }

            updateRuntimeState(from: sessionsByEndpoint, unreadWindowKeys: unreadWindowKeys)

            // Detect agent state for agent-tagged windows
            await detectAgentStates(sessionsByEndpoint: sessionsByEndpoint)
        }

        // Update worktree fields from git status
        updateWorktreeGitStatus(gitStatuses)

        // Refresh GitHub PR info: the selected worktree inline (it drives the
        // visible strip), the rest in a background sweep so every sidebar row
        // can show its PR badge without ever having been selected.
        if let selectedId = appState.uiState.selectedWorktreeId {
            await refreshPullRequest(for: selectedId)
        }
        Task { await sweepPullRequests() }

        // Roll up unread counts and aggregate badges
        updateUnreadCounts()
        updateAggregatedBadges()

        // Check for notification-worthy badge transitions
        await checkNotifications()

        // Update dock badge with aggregate unread count
        updateDockBadge()
    }

    /// Update runtime windows from tmux session data.
    /// Preserves existing `hasUnreadOutput` state and merges newly detected unread windows.
    /// Preserves existing tags or infers them from window names.
    private func updateRuntimeState(
        from sessionsByEndpoint: [String: [TmuxSession]],
        unreadWindowKeys: Set<String> = []
    ) {
        // Build lookup of existing unread state and tags
        let previousUnread: [String: Bool] = Dictionary(
            appState.runtimeWindows.map { ($0.tmuxWindowId, $0.hasUnreadOutput) },
            uniquingKeysWith: { first, _ in first }
        )
        let previousTags: [String: WindowTag?] = Dictionary(
            appState.runtimeWindows.map { ($0.tmuxWindowId, $0.tag) },
            uniquingKeysWith: { first, _ in first }
        )

        var runtimeWindows: [RuntimeWindow] = []
        var runtimePanes: [RuntimePane] = []
        var seenWindowIDs = Set<String>()

        for worktree in appState.worktrees {
            guard let sessionName = worktree.tmuxSessionName else { continue }
            let endpointKey = endpointKey(for: worktree)
            let sessions = sessionsByEndpoint[endpointKey] ?? []
            guard let session = sessions.first(where: { $0.name == sessionName }) else { continue }

            for tmuxWindow in session.windows {
                let namespacedId = namespacedWindowId(rawWindowId: tmuxWindow.windowId, worktree: worktree)
                guard seenWindowIDs.insert(namespacedId).inserted else { continue }
                let unreadKey = "\(worktree.id):\(tmuxWindow.windowId)"
                // Window is unread if: newly detected OR was previously unread
                let isUnread = unreadWindowKeys.contains(unreadKey)
                    || (previousUnread[namespacedId] ?? false)
                let badge = StatusAggregator.windowBadge(hasUnreadOutput: isUnread)

                // Preserve existing tag or infer from window name
                let tag: WindowTag? = if let existing = previousTags[namespacedId] {
                    existing
                } else {
                    WindowTag.infer(from: tmuxWindow.name)
                }

                let rw = RuntimeWindow(
                    tmuxWindowId: namespacedId,
                    tmuxWindowRawId: tmuxWindow.windowId,
                    worktreeId: worktree.id,
                    tmuxWindowIndex: tmuxWindow.windowIndex,
                    title: tmuxWindow.name,
                    activePaneId: tmuxWindow.panes.first(where: \.isActive)?.paneId,
                    paneCount: tmuxWindow.panes.count,
                    hasUnreadOutput: isUnread,
                    badge: badge,
                    tag: tag
                )
                runtimeWindows.append(rw)

                runtimePanes.append(contentsOf: tmuxWindow.panes.map { pane in
                    RuntimePane(
                        tmuxPaneId: pane.paneId,
                        tmuxWindowId: namespacedId,
                        title: pane.title,
                        cwd: pane.currentPath,
                        tty: pane.tty,
                        isActive: pane.isActive,
                        agentState: mapHookState(pane.agentState ?? ""),
                        detectedAgent: pane.agentName
                    )
                })
            }
        }

        appState.runtimeWindows = runtimeWindows
        appState.runtimePanes = runtimePanes
    }

    // MARK: - Agent State Detection

    /// Read agent state from tmux pane options (set by Mori hook scripts).
    /// No capture-pane or process scanning — hooks report state directly.
    /// Also cleans up stale agent state when the agent has exited.
    private func detectAgentStates(sessionsByEndpoint: [String: [TmuxSession]]) async {
        let now = Date().timeIntervalSince1970
        var updatedWorktrees = appState.worktrees
        var updatedWindows = appState.runtimeWindows
        var stalePaneCleanups: [(worktree: Worktree, paneId: String)] = []

        // Reset worktree agentState before re-aggregating from windows.
        // Reassigning the full arrays at the end ensures Swift Observation
        // notices the change and refreshes SwiftUI rows.
        for i in updatedWorktrees.indices {
            updatedWorktrees[i].agentState = .none
        }

        for i in updatedWindows.indices {
            let rw = updatedWindows[i]
            guard let worktree = updatedWorktrees.first(where: { $0.id == rw.worktreeId }) else { continue }
            let endpointKey = endpointKey(for: worktree)
            let sessions = sessionsByEndpoint[endpointKey] ?? []
            let rawWindowId = rawWindowId(from: rw)

            guard let (_, tmuxWindow) = findTmuxWindow(
                windowId: rawWindowId,
                in: sessions
            ) else { continue }

            guard !tmuxWindow.panes.isEmpty else { continue }

            var windowIsRunning = false
            var windowIsLongRunning = false
            var windowAgentState: AgentState = .none
            var windowDetectedAgent: String? = nil
            var windowTag = rw.tag

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
                        // Agent exited — queue stale option cleanup after state updates
                        stalePaneCleanups.append((worktree: worktree, paneId: pane.paneId))
                    }
                }
            }

            // Auto-upgrade tag to .agent when a coding agent is detected
            if windowDetectedAgent != nil && windowTag != .agent {
                windowTag = .agent
            }

            let badge = StatusAggregator.windowBadge(
                hasUnreadOutput: rw.hasUnreadOutput,
                isRunning: windowIsRunning,
                isLongRunning: windowIsLongRunning,
                agentState: windowAgentState
            )

            updatedWindows[i].tag = windowTag
            updatedWindows[i].isRunning = windowIsRunning
            updatedWindows[i].isLongRunning = windowIsLongRunning
            updatedWindows[i].agentState = windowAgentState
            updatedWindows[i].detectedAgent = windowDetectedAgent
            updatedWindows[i].badge = badge

            if windowAgentState != .none,
               let worktreeIndex = updatedWorktrees.firstIndex(where: { $0.id == rw.worktreeId }) {
                let current = updatedWorktrees[worktreeIndex].agentState
                if agentStatePriority(windowAgentState) > agentStatePriority(current) {
                    updatedWorktrees[worktreeIndex].agentState = windowAgentState
                }
            }
        }

        appState.worktrees = updatedWorktrees
        appState.runtimeWindows = updatedWindows

        for cleanup in stalePaneCleanups {
            await clearStaleAgentState(worktree: cleanup.worktree, paneId: cleanup.paneId)
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
        case "waiting": return .waitingForInput
        case "done": return .completed
        default: return .none
        }
    }

    /// Clear stale pane options when agent has exited (pane returned to shell).
    /// Re-enables automatic-rename so tmux picks up the current process name.
    private func clearStaleAgentState(worktree: Worktree, paneId: String) async {
        let tmux = tmuxBackend(for: worktree)
        // Unset state and name concurrently (independent operations)
        async let _ = try? tmux.unsetPaneOption(paneId: paneId, option: "@mori-agent-state")
        async let _ = try? tmux.unsetPaneOption(paneId: paneId, option: "@mori-agent-name")

        // Re-enable automatic-rename so tmux sets the window name
        // to the current process (e.g. zsh) instead of the stale agent name.
        try? await tmux.setWindowOption(paneId: paneId, option: "automatic-rename", value: "on")
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

    /// The branch a worktree's diff badge and merge probe compare against:
    /// the project's main-worktree branch. nil for the main worktree itself,
    /// which shows only its uncommitted changes.
    private func baseRef(for worktree: Worktree) -> String? {
        guard !worktree.isMainWorktree else { return nil }
        let base = appState.worktrees
            .first { $0.projectId == worktree.projectId && $0.isMainWorktree }?
            .branch
        // Diffing a branch against itself would always read as zero — skip.
        return base == worktree.branch ? nil : base
    }

    /// Update worktree git status fields from polled results and persist changes.
    private func updateWorktreeGitStatus(_ snapshots: [UUID: WorktreeGitSnapshot]) {
        for i in appState.worktrees.indices {
            guard let snapshot = snapshots[appState.worktrees[i].id] else { continue }
            // The poll snapshot predates several awaits; the row may have
            // flipped to a transient status (deletion started) since. Its git
            // fields are about to be meaningless — don't touch or save them.
            guard !appState.worktrees[i].status.isTransient else { continue }
            let status = snapshot.status
            let wt = appState.worktrees[i]
            let diff = snapshot.diff
            let changed = wt.hasUncommittedChanges != status.isDirty
                || wt.aheadCount != status.ahead
                || wt.behindCount != status.behind
                || wt.stagedCount != status.stagedCount
                || wt.modifiedCount != status.modifiedCount
                || wt.untrackedCount != status.untrackedCount
                || wt.hasUpstream != (status.upstream != nil)
                || (diff != nil && (wt.additions != diff!.additions
                    || wt.deletions != diff!.deletions
                    || wt.hasMergeConflicts != diff!.hasMergeConflicts))

            if changed {
                appState.worktrees[i].hasUncommittedChanges = status.isDirty
                appState.worktrees[i].aheadCount = status.ahead
                appState.worktrees[i].behindCount = status.behind
                appState.worktrees[i].stagedCount = status.stagedCount
                appState.worktrees[i].modifiedCount = status.modifiedCount
                appState.worktrees[i].untrackedCount = status.untrackedCount
                appState.worktrees[i].hasUpstream = status.upstream != nil
                if let diff {
                    appState.worktrees[i].additions = diff.additions
                    appState.worktrees[i].deletions = diff.deletions
                    appState.worktrees[i].hasMergeConflicts = diff.hasMergeConflicts
                }
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
    private func checkNotifications() async {
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

                await notificationManager.notify(
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
        let tmux = tmuxBackend(for: worktree)
        do {
            let sessionReady = await ensureTmuxSession(for: worktree, showErrors: true)
            guard sessionReady else { return }
            _ = try await tmux.createWindow(
                sessionId: sessionName,
                name: nil,
                cwd: worktree.path,
                environment: moriPaneEnvironment(for: worktree)
            )
            await refreshRuntimeState()
            // Re-attach terminal to the (possibly recreated) session
            onTerminalSwitch?(sessionName, worktree.path, location(for: worktree))

            // Fire onWindowCreate hook
            fireHook(event: .onWindowCreate, worktreeId: worktree.id)
        } catch {
            showTmuxOperationError(
                title: .localized("Failed to create window"),
                error: error,
                worktree: worktree
            )
        }
    }

    /// Split the active pane in the current session.
    func splitCurrentPane(horizontal: Bool) async {
        guard let worktree = selectedWorktree,
              let sessionName = worktree.tmuxSessionName else { return }
        let tmux = tmuxBackend(for: worktree)

        do {
            let sessionReady = await ensureTmuxSession(for: worktree, showErrors: true)
            guard sessionReady else { return }
            // Target the session — tmux splits whatever pane is currently active.
            // Don't use cached findActivePaneId which can be stale between polls.
            _ = try await tmux.splitPane(
                sessionId: sessionName,
                paneId: "",
                horizontal: horizontal,
                cwd: worktree.path,
                environment: moriPaneEnvironment(for: worktree)
            )
            await refreshRuntimeState()
        } catch {
            showTmuxOperationError(
                title: .localized("Failed to split pane"),
                error: error,
                worktree: worktree
            )
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
        let tmux = tmuxBackend(for: worktree)
        let windowsInSession = appState.runtimeWindows.filter { $0.worktreeId == worktree.id }
        let activeWindow = windowsInSession.first(where: { $0.tmuxWindowId == appState.uiState.selectedWindowId })
            ?? windowsInSession.first

        // Keep at least one pane alive per worktree session.
        if windowsInSession.count <= 1, (activeWindow?.paneCount ?? 1) <= 1 {
            return
        }

        do {
            // Target the session — tmux kills whatever pane is currently active.
            // Don't use cached findActivePaneId which can be stale between polls.
            try await tmux.killPane(sessionId: sessionName, paneId: sessionName)
            await refreshRuntimeState()

            // If the session was killed (last pane in last window), detach
            let stillHasWindows = appState.runtimeWindows.contains { $0.worktreeId == worktree.id }
            if !stillHasWindows {
                appState.uiState.selectedWindowId = nil
                onTerminalDetach?()
            }
        } catch {
            showErrorAlert(title: .localized("Failed to close pane"), message: error.localizedDescription)
        }
    }

    /// Close the currently selected tmux window.
    /// If it's the last window, kills the session and shows empty state.
    func closeCurrentWindow() async {
        guard let worktree = selectedWorktree,
              let sessionName = worktree.tmuxSessionName,
              let windowId = appState.uiState.selectedWindowId else { return }
        let tmux = tmuxBackend(for: worktree)

        let cachedWindowsInSession = appState.runtimeWindows.filter { $0.worktreeId == worktree.id }
        let liveWindowCount = await actualWindowCount(for: worktree, sessionName: sessionName)
        let windowCount = liveWindowCount ?? cachedWindowsInSession.count
        if windowCount <= 1 {
            return
        }

        // Fire onWindowClose hook before kill
        let windowTitle = appState.runtimeWindows
            .first(where: { $0.tmuxWindowId == windowId })?.title ?? ""
        fireHook(event: .onWindowClose, worktreeId: worktree.id, windowName: windowTitle)

        do {
            let rawWindowId = WorkspaceEndpoint.rawWindowId(from: windowId)
            try await tmux.killWindow(sessionId: sessionName, windowId: rawWindowId)
            appState.uiState.selectedWindowId = nil
            await refreshRuntimeState()
            // Auto-select the first remaining window
            if let first = appState.runtimeWindows.first(where: { $0.worktreeId == worktree.id }) {
                selectWindow(first.tmuxWindowId)
            }
        } catch {
            showErrorAlert(title: .localized("Failed to close window"), message: error.localizedDescription)
        }
    }

    /// Close a specific tmux window by its ID (from sidebar context menu).
    func closeWindow(windowId: String) async {
        guard let rw = appState.runtimeWindows.first(where: { $0.tmuxWindowId == windowId }),
              let worktree = appState.worktrees.first(where: { $0.id == rw.worktreeId }),
              let sessionName = worktree.tmuxSessionName else { return }
        let tmux = tmuxBackend(for: worktree)
        let rawWindowId = rawWindowId(from: rw)

        let cachedWindowsInSession = appState.runtimeWindows.filter { $0.worktreeId == worktree.id }
        let liveWindowCount = await actualWindowCount(for: worktree, sessionName: sessionName)
        let windowCount = liveWindowCount ?? cachedWindowsInSession.count
        if windowCount <= 1 {
            return
        }

        fireHook(event: .onWindowClose, worktreeId: worktree.id, windowName: rw.title)

        do {
            try await tmux.killWindow(sessionId: sessionName, windowId: rawWindowId)
            await refreshRuntimeState()
            if windowId == appState.uiState.selectedWindowId {
                appState.uiState.selectedWindowId = nil
                if let first = appState.runtimeWindows.first(where: { $0.worktreeId == worktree.id }) {
                    selectWindow(first.tmuxWindowId)
                }
            }
        } catch {
            showErrorAlert(title: .localized("Failed to close window"), message: error.localizedDescription)
        }
    }

    /// Launch a CLI tool in the currently selected worktree's tmux session.
    func launchToolInCurrentSession(
        command: String,
        resolvedLocalCommand: String? = nil,
        windowName: String
    ) async {
        guard let worktree = appState.selectedWorktree,
              let sessionName = worktree.tmuxSessionName else { return }
        let tmux = tmuxBackend(for: worktree)
        let launchCommand = toolLaunchCommand(
            command: command,
            resolvedLocalCommand: resolvedLocalCommand,
            location: location(for: worktree)
        )
        do {
            let newWindow = try await tmux.createWindow(
                sessionId: sessionName,
                name: windowName,
                cwd: worktree.path,
                environment: moriPaneEnvironment(for: worktree)
            )
            try await tmux.sendKeys(
                sessionId: sessionName,
                paneId: newWindow.windowId,
                keys: launchCommand
            )
            await refreshRuntimeState()
        } catch {
            // Best effort — tool may not be available in tmux PATH
        }
    }

    // MARK: - Window Navigation Helpers

    private var selectedWorktree: Worktree? {
        guard let id = appState.uiState.selectedWorktreeId else { return nil }
        return appState.worktrees.first { $0.id == id }
    }

    func companionToolLaunchContext() -> CompanionToolLaunchContext? {
        guard let worktree = selectedWorktree else { return nil }
        return CompanionToolLaunchContext(
            workspaceID: worktree.id.uuidString,
            workingDirectory: activePaneCwd() ?? worktree.path,
            location: location(for: worktree)
        )
    }

    /// Whether a worktree is currently selected (used to decide empty-state UI).
    var hasSelectedWorktree: Bool {
        selectedWorktree != nil
    }

    /// Recreate the tmux session for the current worktree and re-attach the terminal.
    /// Returns true when re-attach succeeded.
    @discardableResult
    func reconnectCurrentSession(showErrors: Bool = true) async -> Bool {
        guard let worktree = selectedWorktree else { return false }
        let sessionReady = await ensureTmuxSession(for: worktree, showErrors: showErrors)
        guard sessionReady else {
            onTerminalDetach?()
            return false
        }
        await refreshRuntimeState()
        if let sessionName = worktree.tmuxSessionName {
            onTerminalSwitch?(sessionName, worktree.path, location(for: worktree))
        }
        return true
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
        guard let worktree = selectedWorktree else { return nil }
        let sessions = sessionsForEndpoint(of: worktree)
        guard let session = sessions.first(where: { $0.name == sessionName }) else { return nil }
        for window in session.windows {
            if let pane = window.panes.first(where: { $0.isActive }) {
                return pane.paneId
            }
        }
        return session.windows.first?.panes.first?.paneId
    }

    /// Fetch live window count for a session from tmux to avoid stale UI races.
    private func actualWindowCount(for worktree: Worktree, sessionName: String) async -> Int? {
        let tmux = tmuxBackend(for: worktree)
        let sessions = try? await tmux.scanAll()
        return sessions?.first(where: { $0.name == sessionName })?.windows.count
    }

    /// Open a CLI tool (e.g. lazygit, yazi) in a new tmux window at the active pane's cwd.
    /// Retained for fallback flows; the primary Mori UI now prefers the companion pane.
    func openToolWindow(command: String) async {
        guard let worktree = selectedWorktree,
              let sessionName = worktree.tmuxSessionName else { return }
        let tmux = tmuxBackend(for: worktree)

        // Resolve cwd from the active pane, falling back to worktree path
        let cwd = activePaneCwd() ?? worktree.path
        let workspaceLocation = location(for: worktree)
        let resolvedLocalCommand = workspaceLocation == .local
            ? BinaryResolver.resolveTool(command: command)
            : nil
        let launchCommand = toolLaunchCommand(
            command: command,
            resolvedLocalCommand: resolvedLocalCommand,
            location: workspaceLocation
        )

        do {
            let sessionReady = await ensureTmuxSession(for: worktree, showErrors: true)
            guard sessionReady else { return }
            let window = try await tmux.createWindow(
                sessionId: sessionName,
                name: command,
                cwd: cwd,
                environment: moriPaneEnvironment(for: worktree)
            )
            try await tmux.sendKeys(sessionId: sessionName, paneId: window.windowId, keys: launchCommand)
            await refreshRuntimeState()
            onTerminalSwitch?(sessionName, worktree.path, location(for: worktree))
        } catch {
            showTmuxOperationError(
                title: .localized("Failed to open \(command)"),
                error: error,
                worktree: worktree
            )
        }
    }

    /// Returns the cwd of the currently active pane, if available.
    private func activePaneCwd() -> String? {
        guard let windowId = appState.uiState.selectedWindowId else { return nil }
        let panes = appState.panes(forWindow: windowId)
        return panes.first(where: { $0.isActive })?.cwd ?? panes.first?.cwd
    }

    private func toolLaunchCommand(
        command: String,
        resolvedLocalCommand: String?,
        location: WorkspaceLocation
    ) -> String {
        switch location {
        case .local:
            let executable = SSHCommandSupport.shellEscape(resolvedLocalCommand ?? command)
            let pathValue = BinaryResolver.synthesizedPATH()
            let pathExport = pathValue.isEmpty ? "" : "export PATH=\(SSHCommandSupport.shellEscape(pathValue)); "
            return "\(pathExport)exec \(executable)"
        case .ssh:
            return command
        }
    }

    // MARK: - Pane Navigation & Management

    /// Navigate to a pane by direction (up/down/left/right/next/previous).
    func navigatePane(direction: PaneDirection) async {
        guard let worktree = selectedWorktree,
              let sessionName = worktree.tmuxSessionName else { return }
        let tmux = tmuxBackend(for: worktree)
        do {
            try await tmux.navigatePane(sessionId: sessionName, direction: direction)
        } catch {
            // Non-fatal — pane may not exist in that direction
        }
    }

    /// Resize the active pane in the given direction.
    func resizePane(direction: PaneDirection, amount: Int = 10) async {
        guard let worktree = selectedWorktree,
              let sessionName = worktree.tmuxSessionName else { return }
        let tmux = tmuxBackend(for: worktree)
        do {
            try await tmux.resizePane(sessionId: sessionName, direction: direction, amount: amount)
        } catch {
            // Non-fatal
        }
    }

    /// Toggle zoom on the active pane.
    func togglePaneZoom() async {
        guard let worktree = selectedWorktree,
              let sessionName = worktree.tmuxSessionName else { return }
        let tmux = tmuxBackend(for: worktree)
        do {
            try await tmux.togglePaneZoom(sessionId: sessionName)
        } catch {
            // Non-fatal
        }
    }

    /// Equalize all pane sizes in the active window.
    func equalizePanes() async {
        guard let worktree = selectedWorktree,
              let sessionName = worktree.tmuxSessionName else { return }
        let tmux = tmuxBackend(for: worktree)
        do {
            try await tmux.equalizePanes(sessionId: sessionName)
        } catch {
            // Non-fatal
        }
    }

    // MARK: - Quick Jump (⌘1-9)

    /// Unified sidebar quick jump: selects a worktree by global index across all visible projects.
    func quickJump(index: Int) {
        selectWorktreeByGlobalIndex(index)
    }

    /// Select a worktree by 1-based global index across all projects.
    /// Iterates projects in display order, skipping collapsed ones, to match
    /// the sidebar's ⌘N hints. Index 9 selects the last worktree regardless of count.
    private func selectWorktreeByGlobalIndex(_ index: Int) {
        // Sort pinned-first, Home excluded, to match sidebar display order.
        let repos = appState.projects.filter { !$0.isHomeWorkspace }
        let sortedProjects = repos.filter { $0.isFavorite }
            + repos.filter { !$0.isFavorite }
        let allWorktrees = sortedProjects
            .filter { !$0.isCollapsed }
            .flatMap { project in
                appState.worktrees
                    .filter { $0.projectId == project.id && $0.status != .unavailable }
            }
        guard !allWorktrees.isEmpty else { return }

        let targetIndex = index == 9 ? allWorktrees.count - 1 : index - 1
        guard targetIndex >= 0, targetIndex < allWorktrees.count else { return }

        selectWorktree(allWorktrees[targetIndex].id)
    }


    /// Select a tmux window by 1-based index within the selected worktree.
    /// Index 9 selects the last window regardless of count.
    func selectWindowByIndex(_ index: Int) {
        let windows = appState.windowsForSelectedWorktree
        guard !windows.isEmpty else { return }

        let targetIndex = index == 9 ? windows.count - 1 : index - 1
        guard targetIndex >= 0, targetIndex < windows.count else { return }
        selectWindow(windows[targetIndex].tmuxWindowId)
    }

    // MARK: - Worktree Cycling

    /// Cycle to the next or previous worktree (Ctrl+Tab / Ctrl+Shift+Tab).
    func cycleWorktree(forward: Bool) {
        guard let projectId = appState.uiState.selectedProjectId else { return }
        // Skip transient rows: selectWorktree refuses them, so landing on one
        // would leave the cycle stuck for as long as a deletion runs.
        let projectWorktrees = appState.worktrees
            .filter { $0.projectId == projectId && !$0.status.isTransient }
        guard !projectWorktrees.isEmpty else { return }

        let currentIndex = projectWorktrees.firstIndex(where: {
            $0.id == appState.uiState.selectedWorktreeId
        }) ?? 0

        let offset = forward ? 1 : -1
        let newIndex = (currentIndex + offset + projectWorktrees.count) % projectWorktrees.count
        selectWorktree(projectWorktrees[newIndex].id)
    }

    // MARK: - Session Death Detection

    /// Called during polling to recover a missing session for the selected
    /// worktree, whose terminal is on screen. Returns true when the session was
    /// recreated, so caller can rescan immediately.
    ///
    /// Only the selected worktree: recreating sessions for every active row
    /// would resurrect dozens of login shells after a bulk import or a tmux
    /// server restart. Unselected rows get their session lazily on selection
    /// via ensureTmuxSession().
    func detectAndRecoverDeadSessions(sessionsByEndpoint: [String: [TmuxSession]]) async -> Bool {
        guard let worktree = appState.worktrees.first(where: {
                  $0.id == appState.uiState.selectedWorktreeId && $0.status == .active
              }),
              let sessionName = worktree.tmuxSessionName else { return false }

        let sessions = sessionsByEndpoint[endpointKey(for: worktree)] ?? []
        guard !sessions.contains(where: { $0.name == sessionName }) else { return false }

        let tmux = tmuxBackend(for: worktree)
        let recreated = (try? await tmux.createSession(
            name: sessionName,
            cwd: worktree.path,
            environment: moriPaneEnvironment(for: worktree)
        )) != nil
        guard recreated else { return false }

        await onSessionCreated?(tmux)
        // Force new terminal process; same session key can otherwise
        // keep a dead surface cached after remote shell exit.
        onTerminalDetach?()
        onTerminalSwitch?(sessionName, worktree.path, location(for: worktree))
        return true
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
                let sessionReady = await ensureTmuxSession(for: worktree, showErrors: true)
                await refreshRuntimeState()

                // Notify terminal to attach
                if sessionReady, let sessionName = worktree.tmuxSessionName {
                    onTerminalSwitch?(sessionName, worktree.path, location(for: worktree))
                } else {
                    onTerminalDetach?()
                }

                // 3. Restore selected window (after runtime state is loaded)
                if let savedWindowId = uiState.selectedWindowId {
                    let migratedWindowId = migratedWindowIdIfNeeded(
                        savedWindowId: savedWindowId,
                        worktree: worktree
                    )
                    if let windowId = migratedWindowId,
                       let runtimeWindow = appState.runtimeWindows.first(where: { $0.tmuxWindowId == windowId }) {
                        appState.uiState.selectedWindowId = windowId
                        if windowId != savedWindowId {
                            saveUIState()
                        }
                        // Switch tmux to the saved window
                        if let sessionName = worktree.tmuxSessionName {
                            let rawWindowId = rawWindowId(from: runtimeWindow)
                            let tmux = tmuxBackend(for: worktree)
                            try? await tmux.selectWindow(sessionId: sessionName, windowId: rawWindowId)
                        }
                    }
                }
            }
        }
    }

    /// Migrate pre-remote-namespace persisted IDs (e.g. "@1") to endpoint-scoped IDs
    /// (e.g. "local|@1" or "ssh:user@host|@1") during first restore after upgrade.
    private func migratedWindowIdIfNeeded(
        savedWindowId: String,
        worktree: Worktree
    ) -> String? {
        if appState.runtimeWindows.contains(where: { $0.tmuxWindowId == savedWindowId }) {
            return savedWindowId
        }

        guard !savedWindowId.contains(WorkspaceEndpoint.separator) else {
            return nil
        }

        let candidate = namespacedWindowId(rawWindowId: savedWindowId, worktree: worktree)
        if appState.runtimeWindows.contains(where: { $0.tmuxWindowId == candidate }) {
            return candidate
        }
        return nil
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
