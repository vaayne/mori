import Foundation
import MoriSSH
import MoriTerminal
import Observation
import os.log

private let log = Logger(subsystem: "com.vaayne.mori-remote", category: "Shell")

enum ShellState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case shell

    nonisolated static func == (lhs: ShellState, rhs: ShellState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected),
             (.shell, .shell):
            return true
        default:
            return false
        }
    }
}

enum ShellError: LocalizedError {
    case notConnected
    case missingCredentials
    case connectionTimedOut
    case shellFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return String.localized("SSH connection is not available.")
        case .missingCredentials:
            return String.localized("Saved server credentials are incomplete. Edit the server and enter the password again.")
        case .connectionTimedOut:
            return String.localized("SSH connection timed out. Check the host, password, and network, then try again.")
        case .shellFailed(let reason):
            return String.localized("Shell failed: \(reason)")
        }
    }
}

@MainActor
@Observable
final class ShellCoordinator {
    var state: ShellState = .disconnected
    var lastError: Error?
    var activeServer: Server?

    private var connectionGeneration: UInt64 = 0

    // Tmux state (observable for sidebar)
    var tmuxSessions: [TmuxSession] = []
    var tmuxActiveSession: TmuxSession?
    var tmuxWindows: [TmuxWindow] = []
    var isTmuxActive: Bool { tmuxActiveSession != nil }

    /// The tty of the tmux client backing THIS iOS shell channel (e.g. "/dev/pts/3").
    /// Resolved after attach; used to target switch-client at our own client so
    /// switching never disturbs a desktop client attached to the same server.
    private var iosClientTTY: String?

    /// The session our own client currently views. Seeded from the resolved client,
    /// then updated on every switch we issue (the iOS client only moves via us).
    private var iosCurrentSession: String?

    var isShellActive: Bool { state == .shell }

    private var sshManager: SSHConnectionManager?
    private var shellChannel: SSHChannel?
    private weak var renderer: SwiftTermRenderer?
    private var outputTask: Task<Void, Never>?

    // MARK: - Connect / Disconnect

    func connect(server: Server) async {
        let generation = beginConnectionGeneration()
        await resetConnection()

        guard isCurrentConnection(generation) else { return }

        activeServer = server
        state = .connecting
        lastError = nil

        guard !server.password.isEmpty else {
            lastError = ShellError.missingCredentials
            state = .disconnected
            return
        }

        let manager = SSHConnectionManager()
        do {
            try await withTimeout(seconds: 15) {
                try await manager.connect(
                    host: server.host.trimmingCharacters(in: .whitespacesAndNewlines),
                    port: server.port,
                    user: server.username.trimmingCharacters(in: .whitespacesAndNewlines),
                    auth: .password(server.password)
                )
            }

            guard isCurrentConnection(generation) else {
                await manager.disconnect()
                return
            }

            sshManager = manager
            state = .connected
        } catch {
            await manager.disconnect()
            guard isCurrentConnection(generation) else { return }
            lastError = error
            state = .disconnected
        }
    }

    func disconnect() async {
        let generation = beginConnectionGeneration()
        await resetConnection()
        guard isCurrentConnection(generation) else { return }
        state = .disconnected
    }

    // MARK: - Shell

    func openShell(renderer: SwiftTermRenderer) async {
        let generation = connectionGeneration

        guard case .connected = state else {
            if case .shell = state, isCurrentConnection(generation) {
                wireRenderer(renderer)
                renderer.activateKeyboard()
            }
            return
        }
        guard let sshManager else {
            lastError = ShellError.notConnected
            state = .disconnected
            return
        }

        wireRenderer(renderer)

        let size = renderer.gridSize()
        let cols = size.cols > 0 ? Int(size.cols) : 80
        let rows = size.rows > 0 ? Int(size.rows) : 24

        do {
            let channel = try await sshManager.openShellChannel(cols: cols, rows: rows)

            guard isCurrentConnection(generation), activeServer != nil else {
                await channel.close()
                return
            }

            shellChannel = channel

            outputTask = Task { [weak self] in
                do {
                    for try await chunk in channel.inbound {
                        guard let self else { return }
                        guard await self.isCurrentConnection(generation) else { return }
                        await MainActor.run {
                            self.renderer?.feedBytes(chunk)
                        }
                    }
                } catch {
                    log.error("Shell inbound error: \(error)")
                }
                guard let self, !Task.isCancelled else { return }
                guard await self.isCurrentConnection(generation) else { return }
                await self.handleShellClosed(generation: generation)
            }

            state = .shell
            renderer.activateKeyboard()
            attachDefaultSession()
            startTmuxPolling(generation: generation)
        } catch {
            guard isCurrentConnection(generation) else { return }
            await resetConnection()
            lastError = error
            state = .disconnected
        }
    }

    // MARK: - Private

    /// The custom keyboard accessory bar (set by TerminalScreen).
    var accessoryBar: TerminalAccessoryBar?

    private func wireRenderer(_ renderer: SwiftTermRenderer) {
        if let previousRenderer = self.renderer, previousRenderer !== renderer {
            detachAccessoryBar(from: previousRenderer)
        }

        self.renderer = renderer
        renderer.inputHandler = { [weak self] data in
            self?.sendInput(data)
        }
        renderer.sizeChangeHandler = { [weak self] newCols, newRows in
            self?.sendResize(Int(newCols), Int(newRows))
        }

        // Wire the custom accessory bar — must set before activateKeyboard.
        // Reusing the same accessory view across terminal responders is fine,
        // but UIKit stays happier if we explicitly detach it from the previous
        // responder before reassigning it during host switches and reconnects.
        if let bar = accessoryBar {
            let tv = renderer.swiftTermView
            bar.terminalView = tv
            if tv.inputAccessoryView !== bar {
                tv.inputAccessoryView = bar
            }
            if tv.window != nil || tv.isFirstResponder {
                tv.reloadInputViews()
            }
            bar.onTmuxCommand = { [weak self] cmd in
                self?.handleTmuxCommand(cmd)
            }
        }
    }

    private func detachAccessoryBar(from renderer: SwiftTermRenderer?) {
        guard let accessoryBar else { return }

        if let renderer {
            let terminalView = renderer.swiftTermView
            if terminalView.inputAccessoryView != nil {
                terminalView.inputAccessoryView = nil
                if terminalView.window != nil || terminalView.isFirstResponder {
                    terminalView.reloadInputViews()
                }
            }

            if accessoryBar.terminalView === terminalView {
                accessoryBar.terminalView = nil
            }
        } else {
            accessoryBar.terminalView = nil
        }

        accessoryBar.onTmuxCommand = nil
    }

    private func sendInput(_ data: Data) {
        guard let shellChannel else { return }
        Task {
            do {
                try await shellChannel.write(data)
            } catch {
                log.error("sendInput error: \(error)")
            }
        }
    }

    private func sendResize(_ cols: Int, _ rows: Int) {
        guard cols > 0, rows > 0, let shellChannel else { return }
        Task {
            try? await shellChannel.resize(cols: cols, rows: rows)
        }
    }

    // MARK: - Tmux

    private var tmuxPollTask: Task<Void, Never>?

    func handleTmuxCommand(_ command: TmuxCommand) {
        guard state == .shell, shellChannel != nil else {
            log.debug("Ignoring tmux command while shell is inactive")
            return
        }

        let generation = connectionGeneration

        // Send tmux CLI commands through the shell channel (not exec).
        // The shell is running INSIDE tmux, so $TMUX is set and commands
        // correctly target the current session/window/pane.
        // Ctrl-U clears any partial input, then we run the command.
        let cmd = command.shellCommand()
        log.info("Tmux command via shell: \(cmd)")
        let sequence = "\u{15}\(cmd)\n"
        sendInput(Data(sequence.utf8))

        // Refresh tmux state after a short delay.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self, await self.isCurrentConnection(generation) else { return }
            await self.pollTmuxState(generation: generation)
        }
    }

    /// Attach this shell channel to the server's default tmux session, creating it
    /// if needed. Only attaches when the shell is not already inside tmux, so a
    /// user whose login shell auto-attaches keeps their existing session.
    private func attachDefaultSession() {
        guard let session = activeServer?.defaultSession.trimmingCharacters(in: .whitespacesAndNewlines),
              !session.isEmpty else { return }
        iosCurrentSession = session
        let cmd = "[ -z \"$TMUX\" ] && exec tmux new-session -A -s '\(session)'"
        let sequence = "\u{15}\(cmd)\n"
        sendInput(Data(sequence.utf8))
    }

    /// Resolve the tty of the tmux client backing this shell channel, so that
    /// switch-client can target our own client by `-c <tty>`.
    private func resolveClientTTY(generation: UInt64) async {
        guard isCurrentConnection(generation), let sshManager, await sshManager.isConnected else { return }
        let target = activeServer?.defaultSession.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        do {
            let raw = try await sshManager.runCommandNoPTY(
                tmuxCmd("list-clients -F '#{client_tty}\(fs)#{client_session}' 2>/dev/null")
            )
            guard isCurrentConnection(generation) else { return }
            let clients = raw.split(separator: "\n").compactMap { line -> (tty: String, session: String)? in
                let p = line.components(separatedBy: fs)
                guard p.count >= 2, !p[0].isEmpty else { return nil }
                return (p[0], p[1])
            }
            guard !clients.isEmpty else { return }
            // Prefer the client attached to our default session; else the sole client.
            let match = clients.first(where: { $0.session == target }) ?? (clients.count == 1 ? clients.first : nil)
            if let match {
                iosClientTTY = match.tty
                iosCurrentSession = match.session
                log.info("Resolved iOS tmux client tty: \(match.tty) (session \(match.session))")
            }
        } catch {
            log.debug("resolveClientTTY failed: \(error)")
        }
    }

    func startTmuxPolling(generation: UInt64) {
        tmuxPollTask?.cancel()
        tmuxPollTask = Task { [weak self] in
            guard let self else { return }
            guard await self.isCurrentConnection(generation) else { return }

            // Give the attach a moment to settle, then resolve our client tty.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, await self.isCurrentConnection(generation) else { return }
            await self.resolveClientTTY(generation: generation)
            guard !Task.isCancelled, await self.isCurrentConnection(generation) else { return }
            await self.pollTmuxState(generation: generation)

            // Poll every 5 seconds using NoPTY exec channels
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled, await self.isCurrentConnection(generation) else { return }
                await self.pollTmuxState(generation: generation)
            }
        }
    }


    /// Build a tmux invocation with common bin locations on PATH. Exec channels
    /// don't source the login profile, so Homebrew's tmux is off PATH — prepend
    /// the usual locations so a bare `tmux` resolves on any standard install.
    /// This avoids depending on a separately-detected path, which login-shell
    /// banner noise can corrupt.
    private func tmuxCmd(_ args: String) -> String {
        "PATH=\"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH\" tmux \(args)"
    }

    /// Field separator for tmux `-F` queries. tmux sanitizes non-printable and
    /// non-ASCII bytes in format output to `_` (both a raw tab and `§` came back
    /// as `_`), so use a printable-ASCII token that survives verbatim and is
    /// vanishingly unlikely to appear in a session/window name, path, or title.
    private let fs = "~|~"

    /// Run a tmux query via NoPTY exec, falling back to PTY exec on failure.
    private func tmuxQuery(_ command: String) async throws -> String {
        guard let sshManager else { throw ShellError.notConnected }
        do {
            return try await sshManager.runCommandNoPTY(command)
        } catch {
            return try await sshManager.runCommand(command)
        }
    }

    private func pollTmuxState(generation: UInt64? = nil) async {
        if let generation, !isCurrentConnection(generation) {
            return
        }

        guard let sshManager, await sshManager.isConnected else {
            log.debug("tmux poll: no SSH manager or disconnected")
            return
        }

        func clearState() {
            accessoryBar?.updateTmux(session: nil, windows: [])
            self.tmuxSessions = []
            self.tmuxActiveSession = nil
            self.tmuxWindows = []
        }

        do {
            // Three bulk queries (fs-delimited): sessions, all windows, all panes.
            let sessionsRaw = try await tmuxQuery(
                tmuxCmd("list-sessions -F '#{session_name}\(fs)#{session_windows}\(fs)#{session_attached}' 2>/dev/null")
            )
            if let generation, !isCurrentConnection(generation) { return }
            guard !sessionsRaw.isEmpty else { clearState(); return }

            // Windows/panes are best-effort: a failure here must not wipe the
            // session list, so fall back to empty instead of throwing out.
            let windowsRaw = (try? await tmuxQuery(
                tmuxCmd("list-windows -a -F '#{session_name}\(fs)#{window_index}\(fs)#{window_name}\(fs)#{window_active}\(fs)#{pane_current_path}' 2>/dev/null")
            )) ?? ""
            if let generation, !isCurrentConnection(generation) { return }

            let panesRaw = (try? await tmuxQuery(
                tmuxCmd("list-panes -a -F '#{session_name}\(fs)#{window_index}\(fs)#{pane_id}\(fs)#{pane_active}\(fs)#{pane_current_command}\(fs)#{pane_title}\(fs)#{pane_current_path}\(fs)#{@mori-agent-state}\(fs)#{@mori-agent-name}' 2>/dev/null")
            )) ?? ""
            if let generation, !isCurrentConnection(generation) { return }

            // Panes grouped by "session\twindowIndex".
            var panesByWindow: [String: [TmuxPane]] = [:]
            for line in panesRaw.split(separator: "\n") {
                let p = line.components(separatedBy: fs)
                guard p.count >= 4 else { continue }
                let key = "\(p[0])\t\(p[1])"
                let pane = TmuxPane(
                    paneId: p[2],
                    isActive: p[3] == "1",
                    command: p.count > 4 ? p[4] : "",
                    title: p.count > 5 ? p[5] : "",
                    path: p.count > 6 ? p[6] : "",
                    agentState: p.count > 7 && !p[7].isEmpty ? p[7] : nil,
                    agentName: p.count > 8 && !p[8].isEmpty ? p[8] : nil
                )
                panesByWindow[key, default: []].append(pane)
            }

            // Windows grouped by session name, panes attached.
            var windowsBySession: [String: [TmuxWindow]] = [:]
            for line in windowsRaw.split(separator: "\n") {
                let p = line.components(separatedBy: fs)
                guard p.count >= 4 else { continue }
                let sessionName = p[0]
                let index = Int(p[1]) ?? 0
                let window = TmuxWindow(
                    index: index,
                    name: p[2],
                    isActive: p[3] == "1",
                    sessionName: sessionName,
                    path: p.count > 4 ? p[4] : "",
                    panes: panesByWindow["\(sessionName)\t\(index)"] ?? []
                )
                windowsBySession[sessionName, default: []].append(window)
            }

            let sessions = sessionsRaw.split(separator: "\n").compactMap { line -> TmuxSession? in
                let p = line.components(separatedBy: fs)
                guard p.count >= 3 else { return nil }
                let name = p[0]
                return TmuxSession(
                    name: name,
                    windowCount: Int(p[1]) ?? 0,
                    isAttached: p[2] == "1",
                    windows: (windowsBySession[name] ?? []).sorted { $0.index < $1.index }
                )
            }

            // The session our own client views (by tty), else first attached, else first.
            let activeSession = resolveActiveSession(among: sessions)
            guard let activeSession else { clearState(); return }
            if let generation, !isCurrentConnection(generation) { return }

            accessoryBar?.updateTmux(session: activeSession, windows: activeSession.windows)
            self.tmuxSessions = sessions
            self.tmuxActiveSession = activeSession
            self.tmuxWindows = activeSession.windows
        } catch {
            // tmux not running — hide the bar
            log.info("tmux poll error: \(error)")
            clearState()
        }
    }

    /// Pick the session this iOS client is viewing: our tracked current session
    /// when it still exists, otherwise the first attached/first session.
    private func resolveActiveSession(among sessions: [TmuxSession]) -> TmuxSession? {
        if let current = iosCurrentSession,
           let match = sessions.first(where: { $0.name == current }) {
            return match
        }
        return sessions.first(where: { $0.isAttached }) ?? sessions.first
    }

    /// `-c '<tty>' ` targeting our own client, or empty when the tty is unknown.
    private var clientFlag: String {
        iosClientTTY.map { "-c '\($0)' " } ?? ""
    }

    /// Switch to a specific tmux window by index in the given session.
    /// `switch-client -t 'session:index'` moves our client to that session AND
    /// selects the window in one step; the attached client repaints to it.
    func selectTmuxWindow(session: String, windowIndex: Int) {
        iosCurrentSession = session
        runTmuxCommand(tmuxCmd("switch-client \(clientFlag)-t '\(session):\(windowIndex)'"))
    }

    /// Switch to a different tmux session.
    func switchTmuxSession(_ sessionName: String) {
        iosCurrentSession = sessionName
        runTmuxCommand(tmuxCmd("switch-client \(clientFlag)-t '\(sessionName)'"))
    }

    /// Switch to a specific pane: move our client to the owning window, then
    /// select the pane (pane ids like `%5` are unique across the server).
    func selectTmuxPane(session: String, windowIndex: Int, paneId: String) {
        iosCurrentSession = session
        runTmuxCommand(tmuxCmd("switch-client \(clientFlag)-t '\(session):\(windowIndex)' \\; select-pane -t '\(paneId)'"))
    }

    /// Close (kill) a tmux window.
    func closeTmuxWindow(session: String, windowIndex: Int) {
        runTmuxCommand(tmuxCmd("kill-window -t '\(session):\(windowIndex)'"))
    }

    /// Create a new tmux window in the active session.
    func newTmuxWindow() {
        if let session = iosCurrentSession {
            runTmuxCommand(tmuxCmd("new-window -t '\(session)'"))
        } else {
            runTmuxCommand(tmuxCmd("new-window"))
        }
    }

    /// Create a new tmux session.
    func newTmuxSession() {
        runTmuxCommand(tmuxCmd("new-session -d"))
    }

    /// Kill (close) a tmux session.
    func closeTmuxSession(_ sessionName: String) {
        runTmuxCommand(tmuxCmd("kill-session -t '\(sessionName)'"))
    }

    /// Rename a tmux session.
    func renameTmuxSession(_ oldName: String, to newName: String) {
        runTmuxCommand(tmuxCmd("rename-session -t '\(oldName)' '\(newName)'"))
    }

    /// Create a new tmux window after a specific window index.
    func newTmuxWindowAfter(session: String, windowIndex: Int) {
        runTmuxCommand(tmuxCmd("new-window -a -t '\(session):\(windowIndex)'"))
    }

    /// Force a tmux state refresh.
    func refreshTmuxState() {
        let generation = connectionGeneration
        Task { [weak self] in
            guard let self, await self.isCurrentConnection(generation) else { return }
            await self.pollTmuxState(generation: generation)
        }
    }

    /// Run a tmux command via NoPTY exec channel and refresh state.
    private func runTmuxCommand(_ cmd: String) {
        guard state == .shell else {
            log.debug("Ignoring tmux exec while shell is inactive")
            return
        }
        guard let sshManager else {
            log.error("runTmuxCommand: no SSH manager")
            return
        }

        let generation = connectionGeneration
        log.info("Tmux exec: \(cmd)")
        Task { [weak self] in
            do {
                _ = try await sshManager.runCommandNoPTY(cmd)
            } catch {
                log.error("Tmux exec failed: \(error)")
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self, await self.isCurrentConnection(generation) else { return }
            await self.pollTmuxState(generation: generation)
        }
    }

    /// Send a tmux command through the shell channel and refresh state.
    private func sendTmuxShellCommand(_ cmd: String) {
        guard state == .shell, shellChannel != nil else {
            log.debug("Ignoring tmux shell command while shell is inactive")
            return
        }

        let generation = connectionGeneration
        log.info("Tmux shell command: \(cmd)")
        let sequence = "\u{15}\(cmd)\n"
        sendInput(Data(sequence.utf8))
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self, await self.isCurrentConnection(generation) else { return }
            await self.pollTmuxState(generation: generation)
        }
    }

    private func handleShellClosed(generation: UInt64) async {
        guard isCurrentConnection(generation) else { return }
        await resetConnection()
        guard isCurrentConnection(generation) else { return }
        lastError = ShellError.shellFailed("Shell session ended.")
        state = .disconnected
    }

    private func resetConnection() async {
        tmuxPollTask?.cancel()
        tmuxPollTask = nil
        outputTask?.cancel()
        outputTask = nil

        renderer?.inputHandler = nil
        renderer?.sizeChangeHandler = nil
        detachAccessoryBar(from: renderer)
        renderer?.deactivateKeyboard()
        renderer = nil

        if let shellChannel {
            self.shellChannel = nil
            await shellChannel.close()
        }

        if let sshManager {
            self.sshManager = nil
            await sshManager.disconnect()
        }

        activeServer = nil
        tmuxSessions = []
        tmuxActiveSession = nil
        tmuxWindows = []
        iosClientTTY = nil
        iosCurrentSession = nil
    }

    private func beginConnectionGeneration() -> UInt64 {
        connectionGeneration &+= 1
        return connectionGeneration
    }

    private func isCurrentConnection(_ generation: UInt64) -> Bool {
        generation == connectionGeneration
    }

    private func withTimeout<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw ShellError.connectionTimedOut
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
