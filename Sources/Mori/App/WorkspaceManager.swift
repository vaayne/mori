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

    var errorDescription: String? {
        switch self {
        case .projectNotFound:
            return "Project not found."
        case .projectNotRemote:
            return "Project is not configured as a remote SSH project."
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
        appState.worktrees = allWorktrees
        appState.uiState = try uiStateRepo.fetch()

        // Backfill missing tmux session names from legacy data so every
        // worktree can be mapped to a stable tmux session.
        backfillWorktreeSessionNamesIfNeeded()
        normalizeConflictingSessionBindingsIfNeeded()

        // Validate project paths — mark unavailable if path no longer exists
        validateProjectPaths()
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

    func rawTmuxWindowId(from runtimeWindow: RuntimeWindow) -> String {
        rawWindowId(from: runtimeWindow)
    }

    func sessionsForWorktree(_ worktree: Worktree) -> [TmuxSession] {
        sessionsForEndpoint(of: worktree)
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

        saveUIState()
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
        var detectedBranch = "main"
        if isRepo {
            commonDir = try await git.gitCommonDir(path: path)
            // Detect the actual current branch
            let gitStatus = try? await git.status(worktreePath: path)
            if let branch = gitStatus?.branch {
                detectedBranch = branch
            }
        }

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
        let sessionName = SessionNaming.sessionName(projectShortName: project.shortName, worktree: detectedBranch)
        let worktree = Worktree(
            projectId: project.id,
            name: detectedBranch,
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
            _ = try? await tmux.createSession(name: sessionName, cwd: path)
            await onSessionCreated?(tmux)
            await tmux.refreshNow()
        }

        // Refresh state
        try loadAll()

        // Select the new project
        selectProject(project.id)

        return project
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
    ///   - template: Session template to apply after tmux session creation.
    @discardableResult
    func createWorktree(
        projectId: UUID,
        branchName: String,
        createBranch: Bool = true,
        baseBranch: String? = nil,
        template: SessionTemplate = TemplateRegistry.basic
    ) async throws -> Worktree {
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
        let projectLocation = location(for: project)
        let git = gitBackend(for: projectLocation)
        let tmux = tmuxBackend(for: projectLocation)

        let projectSlug = SessionNaming.slugify(project.name)
        let branchSlug = SessionNaming.slugify(trimmed)

        // Compute worktree path.
        // Local: ~/.mori/{project-slug}/{branch-slug}
        // Remote SSH: <repo parent>/.mori/{project-slug}/{branch-slug}
        let projectDir: String
        switch projectLocation {
        case .local:
            let moriDir = (NSHomeDirectory() as NSString).appendingPathComponent(".mori")
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

        // Git repos use `git worktree add`; non-git projects fall back to creating
        // a plain directory so remote/local "workspace" creation still works.
        let isGitRepo = try await git.isGitRepo(path: project.repoRootPath)
        if isGitRepo {
            do {
                try await git.addWorktree(
                    repoPath: project.repoRootPath,
                    path: worktreePath,
                    branch: trimmed,
                    createBranch: createBranch,
                    baseBranch: baseBranch
                )
            } catch let gitError as GitError where createBranch && isBranchAlreadyExistsError(gitError, branch: trimmed) {
                // User typed an existing branch but branch metadata was stale/unavailable.
                // Retry as "use existing branch" to keep worksheet creation smooth.
                try await git.addWorktree(
                    repoPath: project.repoRootPath,
                    path: worktreePath,
                    branch: trimmed,
                    createBranch: false,
                    baseBranch: nil
                )
            }
        } else {
            try await git.ensureDirectory(path: worktreePath)
        }

        // Step 2: Create Worktree model and save to DB
        let sessionName = SessionNaming.sessionName(projectShortName: project.shortName, worktree: trimmed)
        let worktree = Worktree(
            projectId: projectId,
            name: trimmed,
            path: worktreePath,
            branch: trimmed,
            isMainWorktree: false,
            tmuxSessionName: sessionName,
            status: .active,
            location: projectLocation
        )
        try worktreeRepo.save(worktree)

        // Step 3: Create tmux session + apply template (partial failure tolerant)
        do {
            _ = try await tmux.createSession(name: sessionName, cwd: worktreePath)
            await onSessionCreated?(tmux)
            let applicator = TemplateApplicator(tmux: tmux)
            try await applicator.apply(
                template: template,
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
                template: request.template
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

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = .localized("Remove worktree \"\(worktree.name)\"?")
        alert.informativeText = .localized("This worktree is at \(worktree.path)")
        alert.addButton(withTitle: .localized("Remove from Mori"))
        alert.addButton(withTitle: .localized("Remove from Mori and Delete Files"))
        alert.addButton(withTitle: .localized("Cancel"))

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
                let git = gitBackend(for: location(for: project))
                do {
                    try await git.removeWorktree(
                        repoPath: project.repoRootPath,
                        path: worktree.path,
                        force: false
                    )
                } catch {
                    let errorAlert = NSAlert()
                    errorAlert.alertStyle = .warning
                    errorAlert.messageText = .localized("Failed to delete worktree files")
                    errorAlert.informativeText = error.localizedDescription
                    errorAlert.addButton(withTitle: .localized("OK"))
                    errorAlert.runModal()
                }
            }

            // Kill tmux session if exists
            if let sessionName = worktree.tmuxSessionName {
                try? await tmuxBackend(for: worktree).killSession(id: sessionName)
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

    // MARK: - Sidebar Mode

    /// Update the sidebar mode (Tasks / Workspaces) and persist.
    func setSidebarMode(_ mode: SidebarMode) {
        appState.uiState.sidebarMode = mode
        saveUIState()
    }

    // MARK: - Workflow Status

    /// Update the workflow status for a worktree and persist the change.
    func setWorkflowStatus(worktreeId: UUID, status: WorkflowStatus) {
        guard let index = appState.worktrees.firstIndex(where: { $0.id == worktreeId }) else { return }
        appState.worktrees[index].workflowStatus = status
        try? worktreeRepo.save(appState.worktrees[index])
    }

    // MARK: - Tmux Integration

    /// Check the actual git branch for a worktree and update if it changed.
    private func refreshWorktreeBranch(worktreeId: UUID) async {
        guard let index = appState.worktrees.firstIndex(where: { $0.id == worktreeId }) else { return }
        let worktree = appState.worktrees[index]

        let git = gitBackend(for: worktree)
        guard let gitStatus = try? await git.status(worktreePath: worktree.path),
              let branch = gitStatus.branch,
              branch != worktree.branch else { return }

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
                _ = try await tmux.createSession(name: sessionName, cwd: worktree.path)
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
                _ = try await tmux.createWindow(sessionId: sessionName, name: nil, cwd: worktree.path)
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
        async let tmuxResult: [String: [TmuxSession]] = self.scanSessionsByEndpoint()
        async let gitResult: [UUID: GitStatusInfo] = {
            await self.gitStatusCoordinator.pollAll(
                worktrees: self.appState.worktrees,
                backendForWorktree: { worktree in
                    self.gitBackend(for: worktree)
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
    private func detectAgentStates(sessionsByEndpoint: [String: [TmuxSession]]) async {
        let now = Date().timeIntervalSince1970

        // Reset worktree agentState before re-aggregating from windows
        for i in appState.worktrees.indices {
            appState.worktrees[i].agentState = .none
        }

        for i in appState.runtimeWindows.indices {
            let rw = appState.runtimeWindows[i]
            guard let worktree = appState.worktrees.first(where: { $0.id == rw.worktreeId }) else { continue }
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
                        await clearStaleAgentState(worktree: worktree, paneId: pane.paneId)
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

    /// Update worktree git status fields from polled results and persist changes.
    private func updateWorktreeGitStatus(_ statuses: [UUID: GitStatusInfo]) {
        for i in appState.worktrees.indices {
            guard let status = statuses[appState.worktrees[i].id] else { continue }
            let wt = appState.worktrees[i]
            let changed = wt.hasUncommittedChanges != status.isDirty
                || wt.aheadCount != status.ahead
                || wt.behindCount != status.behind
                || wt.stagedCount != status.stagedCount
                || wt.modifiedCount != status.modifiedCount
                || wt.untrackedCount != status.untrackedCount
                || wt.hasUpstream != (status.upstream != nil)

            if changed {
                appState.worktrees[i].hasUncommittedChanges = status.isDirty
                appState.worktrees[i].aheadCount = status.ahead
                appState.worktrees[i].behindCount = status.behind
                appState.worktrees[i].stagedCount = status.stagedCount
                appState.worktrees[i].modifiedCount = status.modifiedCount
                appState.worktrees[i].untrackedCount = status.untrackedCount
                appState.worktrees[i].hasUpstream = status.upstream != nil
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
            _ = try await tmux.createWindow(sessionId: sessionName, name: nil, cwd: worktree.path)
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
                cwd: worktree.path
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
    /// The window auto-names after the tool and closes when the tool exits.
    func openToolWindow(command: String) async {
        guard let worktree = selectedWorktree,
              let sessionName = worktree.tmuxSessionName else { return }
        let tmux = tmuxBackend(for: worktree)

        // Resolve cwd from the active pane, falling back to worktree path
        let cwd = activePaneCwd() ?? worktree.path

        do {
            let sessionReady = await ensureTmuxSession(for: worktree, showErrors: true)
            guard sessionReady else { return }
            let window = try await tmux.createWindow(sessionId: sessionName, name: command, cwd: cwd)
            try await tmux.sendKeys(sessionId: sessionName, paneId: window.windowId, keys: command)
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

    /// Called during polling to detect and recover missing sessions for active worktrees.
    /// Returns true when any session was recreated, so caller can rescan immediately.
    func detectAndRecoverDeadSessions(sessionsByEndpoint: [String: [TmuxSession]]) async -> Bool {
        var recoveredAny = false

        for worktree in appState.worktrees where worktree.status == .active {
            guard let sessionName = worktree.tmuxSessionName else { continue }
            let endpointKey = endpointKey(for: worktree)
            let sessions = sessionsByEndpoint[endpointKey] ?? []
            let sessionAlive = sessions.contains { $0.name == sessionName }
            guard !sessionAlive else { continue }

            let tmux = tmuxBackend(for: worktree)
            let recreated = (try? await tmux.createSession(name: sessionName, cwd: worktree.path)) != nil
            guard recreated else { continue }

            recoveredAny = true
            await onSessionCreated?(tmux)

            if worktree.id == appState.uiState.selectedWorktreeId {
                // Force new terminal process; same session key can otherwise
                // keep a dead surface cached after remote shell exit.
                onTerminalDetach?()
                onTerminalSwitch?(sessionName, worktree.path, location(for: worktree))
            }
        }

        return recoveredAny
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
