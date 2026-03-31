import Foundation
import MoriSSH
import MoriTerminal
import Observation
import os.log

private let log = Logger(subsystem: "com.vaayne.mori", category: "Shell")

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
    case shellFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return String.localized("SSH connection is not available.")
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

    // Tmux state (observable for sidebar)
    var tmuxSessions: [TmuxSession] = []
    var tmuxActiveSession: TmuxSession?
    var tmuxWindows: [TmuxWindow] = []
    var isTmuxActive: Bool { tmuxActiveSession != nil }

    /// Whether the shell is currently inside a tmux session (attached).
    /// True when the active session reports as attached.
    var isTmuxAttached: Bool { tmuxActiveSession?.isAttached == true }

    var isShellActive: Bool { state == .shell }

    private var sshManager: SSHConnectionManager?
    private var shellChannel: SSHChannel?
    private weak var renderer: SwiftTermRenderer?
    private var outputTask: Task<Void, Never>?

    // MARK: - Connect / Disconnect

    func connect(server: Server) async {
        await resetConnection()
        activeServer = server
        state = .connecting
        lastError = nil

        let manager = SSHConnectionManager()
        do {
            try await manager.connect(
                host: server.host.trimmingCharacters(in: .whitespacesAndNewlines),
                port: server.port,
                user: server.username.trimmingCharacters(in: .whitespacesAndNewlines),
                auth: .password(server.password)
            )
            sshManager = manager
            state = .connected
        } catch {
            await manager.disconnect()
            lastError = error
            state = .disconnected
        }
    }

    func disconnect() async {
        await resetConnection()
        state = .disconnected
    }

    // MARK: - Shell

    func openShell(renderer: SwiftTermRenderer) async {
        guard case .connected = state else {
            if case .shell = state {
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
            shellChannel = channel

            outputTask = Task { [weak self] in
                do {
                    for try await chunk in channel.inbound {
                        guard let self else { return }
                        self.renderer?.feedBytes(chunk)
                    }
                } catch {
                    log.error("Shell inbound error: \(error)")
                }
                guard let self, !Task.isCancelled else { return }
                await self.handleShellClosed()
            }

            state = .shell
            renderer.activateKeyboard()
            startTmuxPolling()
        } catch {
            await resetConnection()
            lastError = error
            state = .disconnected
        }
    }

    // MARK: - Private

    /// The custom keyboard accessory bar (set by TerminalScreen).
    var accessoryBar: TerminalAccessoryBar?

    private func wireRenderer(_ renderer: SwiftTermRenderer) {
        self.renderer = renderer
        renderer.inputHandler = { [weak self] data in
            self?.sendInput(data)
        }
        renderer.sizeChangeHandler = { [weak self] newCols, newRows in
            self?.sendResize(Int(newCols), Int(newRows))
        }

        // Wire the custom accessory bar — must set before activateKeyboard
        if let bar = accessoryBar {
            let tv = renderer.swiftTermView
            bar.terminalView = tv
            tv.inputAccessoryView = bar
            // Force the keyboard to pick up the new accessory view
            tv.reloadInputViews()
            bar.onTmuxCommand = { [weak self] cmd in
                self?.handleTmuxCommand(cmd)
            }
        }
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
        // Send tmux CLI commands through the shell channel (not exec).
        // The shell is running INSIDE tmux, so $TMUX is set and commands
        // correctly target the current session/window/pane.
        // Ctrl-U clears any partial input, then we run the command.
        let cmd = command.shellCommand()
        log.info("Tmux command via shell: \(cmd)")
        let sequence = "\u{15}\(cmd)\n"
        sendInput(Data(sequence.utf8))

        // Refresh tmux state after a short delay
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await self.pollTmuxState()
        }
    }

    func startTmuxPolling() {
        tmuxPollTask?.cancel()
        tmuxPollTask = Task {
            // Detect tmux path first
            await self.detectTmuxPath()

            // Initial poll after shell starts
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await self.pollTmuxState()

            // Poll every 5 seconds using NoPTY exec channels
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                await self.pollTmuxState()
            }
        }
    }

    /// Resolved full path to tmux binary (exec channels don't have user's PATH).
    private var tmuxPath: String = "tmux"

    private func detectTmuxPath() async {
        guard let sshManager, await sshManager.isConnected else { return }
        // Try common paths — exec channels don't source .zshrc/.bashrc
        let candidates = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux",
            "/bin/tmux",
        ]
        do {
            // Use login shell to find the real path
            let result = try await sshManager.runCommandNoPTY(
                "bash -lc 'which tmux' 2>/dev/null || zsh -lc 'which tmux' 2>/dev/null"
            )
            let path = result.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty && !path.contains("not found") {
                tmuxPath = path
                log.info("Detected tmux path: \(path)")
                return
            }
        } catch {
            log.debug("tmux path detection via shell failed: \(error)")
        }
        // Fallback: check common paths directly
        for candidate in candidates {
            do {
                let result = try await sshManager.runCommandNoPTY(
                    "test -x \(candidate) && echo \(candidate)"
                )
                if !result.isEmpty {
                    tmuxPath = candidate
                    log.info("Detected tmux path (fallback): \(candidate)")
                    return
                }
            } catch { continue }
        }
        log.info("Could not detect tmux path, using default: tmux")
    }

    private func pollTmuxState() async {
        guard let sshManager, await sshManager.isConnected else {
            log.debug("tmux poll: no SSH manager or disconnected")
            return
        }

        do {
            // List sessions: "session_name:window_count:attached"
            // Try NoPTY first, fall back to PTY if it fails
            let sessionsRaw: String
            do {
                sessionsRaw = try await sshManager.runCommandNoPTY(
                    "\(tmuxPath) list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}' 2>/dev/null"
                )
            } catch {
                log.debug("NoPTY poll failed, trying with PTY: \(error)")
                sessionsRaw = try await sshManager.runCommand(
                    "\(tmuxPath) list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}' 2>/dev/null"
                )
            }
            log.info("tmux sessions raw: '\(sessionsRaw)'")
            guard !sessionsRaw.isEmpty else {
                accessoryBar?.updateTmux(session: nil, windows: [])
                self.tmuxSessions = []
                self.tmuxActiveSession = nil
                self.tmuxWindows = []
                return
            }

            let sessions = sessionsRaw.split(separator: "\n").compactMap { line -> TmuxSession? in
                let parts = line.split(separator: ":", maxSplits: 2)
                guard parts.count >= 3 else { return nil }
                return TmuxSession(
                    name: String(parts[0]),
                    windowCount: Int(parts[1]) ?? 0,
                    isAttached: parts[2] == "1"
                )
            }

            // Find the attached session (or first)
            let activeSession = sessions.first(where: { $0.isAttached }) ?? sessions.first

            guard let activeSession else {
                accessoryBar?.updateTmux(session: nil, windows: [])
                self.tmuxSessions = []
                self.tmuxActiveSession = nil
                self.tmuxWindows = []
                return
            }

            // Fetch windows for all sessions (for sidebar)
            var enrichedSessions: [TmuxSession] = []
            var activeWindows: [TmuxWindow] = []

            for session in sessions {
                let windowsRaw: String
                do {
                    windowsRaw = try await sshManager.runCommandNoPTY(
                        "\(tmuxPath) list-windows -t '\(session.name)' -F '#{window_index}:#{window_name}:#{window_active}:#{pane_current_path}' 2>/dev/null"
                    )
                } catch {
                    windowsRaw = try await sshManager.runCommand(
                        "\(tmuxPath) list-windows -t '\(session.name)' -F '#{window_index}:#{window_name}:#{window_active}:#{pane_current_path}' 2>/dev/null"
                    )
                }

                let windows = windowsRaw.split(separator: "\n").compactMap { line -> TmuxWindow? in
                    let parts = line.split(separator: ":", maxSplits: 3)
                    guard parts.count >= 3 else { return nil }
                    return TmuxWindow(
                        index: Int(parts[0]) ?? 0,
                        name: String(parts[1]),
                        isActive: parts[2] == "1",
                        sessionName: session.name,
                        path: parts.count >= 4 ? String(parts[3]) : ""
                    )
                }

                var s = session
                s.windows = windows
                enrichedSessions.append(s)

                if session.name == activeSession.name {
                    activeWindows = windows
                }
            }

            accessoryBar?.updateTmux(session: activeSession, windows: activeWindows)
            self.tmuxSessions = enrichedSessions
            self.tmuxActiveSession = activeSession
            self.tmuxWindows = activeWindows
        } catch {
            // tmux not running — hide the bar
            log.info("tmux poll error: \(error)")
            accessoryBar?.updateTmux(session: nil, windows: [])
            self.tmuxSessions = []
            self.tmuxActiveSession = nil
            self.tmuxWindows = []
        }
    }

    /// Switch to a specific tmux window by index in the given session.
    func selectTmuxWindow(session: String, windowIndex: Int) {
        if isTmuxAttached {
            runTmuxCommand("\(tmuxPath) switch-client -t '\(session):\(windowIndex)'")
        } else {
            attachTmuxSession(session, selectWindow: windowIndex)
        }
    }

    /// Switch to a different tmux session.
    func switchTmuxSession(_ sessionName: String) {
        if isTmuxAttached {
            runTmuxCommand("\(tmuxPath) switch-client -t '\(sessionName)'")
        } else {
            attachTmuxSession(sessionName)
        }
    }

    /// Close (kill) a tmux window.
    func closeTmuxWindow(session: String, windowIndex: Int) {
        runTmuxCommand("\(tmuxPath) kill-window -t '\(session):\(windowIndex)'")
    }

    /// Create a new tmux window in the active session.
    func newTmuxWindow() {
        runTmuxCommand("\(tmuxPath) new-window")
    }

    /// Create a new tmux session.
    func newTmuxSession() {
        runTmuxCommand("\(tmuxPath) new-session -d")
    }

    /// Kill (close) a tmux session.
    func closeTmuxSession(_ sessionName: String) {
        runTmuxCommand("\(tmuxPath) kill-session -t '\(sessionName)'")
    }

    /// Rename a tmux session.
    func renameTmuxSession(_ oldName: String, to newName: String) {
        runTmuxCommand("\(tmuxPath) rename-session -t '\(oldName)' '\(newName)'")
    }

    /// Create a new tmux window after a specific window index.
    func newTmuxWindowAfter(session: String, windowIndex: Int) {
        runTmuxCommand("\(tmuxPath) new-window -a -t '\(session):\(windowIndex)'")
    }

    /// Force a tmux state refresh.
    func refreshTmuxState() {
        Task { await pollTmuxState() }
    }

    /// Attach to a tmux session via the shell channel.
    /// Used when not currently inside tmux (switch-client won't work).
    private func attachTmuxSession(_ sessionName: String, selectWindow: Int? = nil) {
        var cmd = "tmux attach-session -t '\(sessionName)'"
        if let win = selectWindow {
            // Select the target window first, then attach
            cmd = "tmux select-window -t '\(sessionName):\(win)' \\; attach-session -t '\(sessionName)'"
        }
        log.info("Tmux attach via shell: \(cmd)")
        let sequence = "\u{15}\(cmd)\n"
        sendInput(Data(sequence.utf8))
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await self.pollTmuxState()
        }
    }

    /// Run a tmux command via NoPTY exec channel and refresh state.
    private func runTmuxCommand(_ cmd: String) {
        guard let sshManager else {
            log.error("runTmuxCommand: no SSH manager")
            return
        }
        log.info("Tmux exec: \(cmd)")
        Task {
            do {
                _ = try await sshManager.runCommandNoPTY(cmd)
            } catch {
                log.error("Tmux exec failed: \(error)")
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            await self.pollTmuxState()
        }
    }

    /// Send a tmux command through the shell channel and refresh state.
    private func sendTmuxShellCommand(_ cmd: String) {
        log.info("Tmux shell command: \(cmd)")
        let sequence = "\u{15}\(cmd)\n"
        sendInput(Data(sequence.utf8))
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await self.pollTmuxState()
        }
    }

    private func handleShellClosed() async {
        await resetConnection()
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
    }
}
