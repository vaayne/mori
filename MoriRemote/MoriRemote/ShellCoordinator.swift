import Foundation
import MoriSSH
import MoriTerminal
import Observation
import os.log

private let log = Logger(subsystem: "dev.mori.remote", category: "Shell")

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
            // TODO: Re-enable tmux polling with a non-blocking approach.
            // The current exec-channel polling interferes with the shell channel.
            // startTmuxPolling()
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
        guard let sshManager else { return }
        Task {
            do {
                // Execute real tmux CLI commands via separate exec channel.
                // No prefix key needed — works regardless of tmux config.
                _ = try await sshManager.runCommand(command.shellCommand)
            } catch {
                log.error("Tmux command error: \(error)")
            }
        }
    }

    func startTmuxPolling() {
        tmuxPollTask?.cancel()
        tmuxPollTask = Task {
            // Initial poll after shell starts
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self.pollTmuxState()

            // Then poll every 3 seconds
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                await self.pollTmuxState()
            }
        }
    }

    private func pollTmuxState() async {
        guard let sshManager, await sshManager.isConnected else {
            log.debug("tmux poll: no SSH manager or disconnected")
            return
        }

        do {
            // List sessions: "session_name:window_count:attached"
            let sessionsRaw = try await sshManager.runCommand(
                "tmux list-sessions -F '#{session_name}:#{session_windows}:#{session_attached}' 2>/dev/null"
            )
            log.debug("tmux sessions raw: '\(sessionsRaw)'")
            guard !sessionsRaw.isEmpty else {
                accessoryBar?.updateTmux(session: nil, windows: [])
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
                return
            }

            // List windows for active session: "index:name:active"
            let windowsRaw = try await sshManager.runCommand(
                "tmux list-windows -t '\(activeSession.name)' -F '#{window_index}:#{window_name}:#{window_active}' 2>/dev/null"
            )

            let windows = windowsRaw.split(separator: "\n").compactMap { line -> TmuxWindow? in
                let parts = line.split(separator: ":", maxSplits: 2)
                guard parts.count >= 3 else { return nil }
                return TmuxWindow(
                    index: Int(parts[0]) ?? 0,
                    name: String(parts[1]),
                    isActive: parts[2] == "1"
                )
            }

            accessoryBar?.updateTmux(session: activeSession, windows: windows)
        } catch {
            // tmux not running — hide the bar
            accessoryBar?.updateTmux(session: nil, windows: [])
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
    }
}
