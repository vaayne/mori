import Foundation
import MoriSSH
import MoriTerminal
import Observation
import os.log

private let log = Logger(subsystem: "dev.mori.remote", category: "Shell")

enum ShellState: Sendable {
    case disconnected(Error?)
    case connecting
    case connected
    case shell
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
    var state: ShellState = .disconnected(nil)

    var stateKey: String {
        switch state {
        case .disconnected: return "disconnected"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .shell: return "shell"
        }
    }

    var isConnecting: Bool {
        if case .connecting = state { return true }
        return false
    }

    var isShellActive: Bool {
        if case .shell = state { return true }
        return false
    }

    private var sshManager: SSHConnectionManager?
    private var shellChannel: SSHChannel?
    private weak var renderer: SwiftTermRenderer?
    private var outputTask: Task<Void, Never>?

    // MARK: - Connect / Disconnect

    func connect(host: String, port: Int, user: String, password: String) async {
        await resetConnection()
        state = .connecting

        let manager = SSHConnectionManager()
        do {
            try await manager.connect(host: host, port: port, user: user, auth: .password(password))
            sshManager = manager
            state = .connected
        } catch {
            await manager.disconnect()
            state = .disconnected(error)
        }
    }

    func disconnect() async {
        await resetConnection()
        state = .disconnected(nil)
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
            state = .disconnected(ShellError.notConnected)
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
        } catch {
            state = .disconnected(error)
        }
    }

    private func wireRenderer(_ renderer: SwiftTermRenderer) {
        self.renderer = renderer
        renderer.inputHandler = { [weak self] data in
            self?.sendInput(data)
        }
        renderer.sizeChangeHandler = { [weak self] newCols, newRows in
            self?.sendResize(Int(newCols), Int(newRows))
        }
    }

    func closeShell() async {
        outputTask?.cancel()
        outputTask = nil

        if let shellChannel {
            self.shellChannel = nil
            await shellChannel.close()
        }

        renderer?.inputHandler = nil
        renderer?.sizeChangeHandler = nil
        renderer = nil

        if let sshManager, await sshManager.isConnected {
            state = .connected
        } else {
            state = .disconnected(nil)
        }
    }

    func runSSHCommand(_ command: String) async throws -> String {
        guard let sshManager else { throw ShellError.notConnected }
        return try await sshManager.runCommand(command)
    }

    // MARK: - Private

    private func sendInput(_ data: Data) {
        guard let shellChannel else {
            log.warning("sendInput: no shell channel")
            return
        }
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

    private func handleShellClosed() async {
        await resetConnection()
        state = .disconnected(ShellError.shellFailed("Shell session ended."))
    }

    private func resetConnection() async {
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
    }
}
