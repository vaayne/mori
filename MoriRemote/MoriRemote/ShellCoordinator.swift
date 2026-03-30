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
        } catch {
            lastError = error
            state = .disconnected
        }
    }

    func runSSHCommand(_ command: String) async throws -> String {
        guard let sshManager else { throw ShellError.notConnected }
        return try await sshManager.runCommand(command)
    }

    // MARK: - Private

    private func wireRenderer(_ renderer: SwiftTermRenderer) {
        self.renderer = renderer
        renderer.inputHandler = { [weak self] data in
            self?.sendInput(data)
        }
        renderer.sizeChangeHandler = { [weak self] newCols, newRows in
            self?.sendResize(Int(newCols), Int(newRows))
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

    private func handleShellClosed() async {
        await resetConnection()
        lastError = ShellError.shellFailed("Shell session ended.")
        state = .disconnected
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

        activeServer = nil
    }
}
