import Foundation
import MoriSSH
import MoriTerminal
import MoriTmux
import Observation

enum SpikeState {
    case disconnected(Error?)
    case connecting
    case connected
    case attached(paneId: String)
}

enum SpikeCoordinatorError: LocalizedError {
    case emptySessionName
    case invalidPort
    case notConnected
    case rendererUnavailable
    case paneUnavailable
    case tmuxExited(String?)

    var errorDescription: String? {
        switch self {
        case .emptySessionName:
            return String.localized("Session name cannot be empty.")
        case .invalidPort:
            return String.localized("Port must be a valid positive number.")
        case .notConnected:
            return String.localized("SSH connection is not available.")
        case .rendererUnavailable:
            return String.localized("Terminal renderer is not ready yet.")
        case .paneUnavailable:
            return String.localized("tmux did not report a pane ID.")
        case .tmuxExited(let reason):
            return reason ?? String.localized("tmux session exited.")
        }
    }
}

@MainActor
@Observable
final class SpikeCoordinator {
    var state: SpikeState = .disconnected(nil)
    var isAttachingSession = false

    private var sshManager: SSHConnectionManager?
    private var sshChannel: SSHChannel?
    private var tmuxClient: TmuxControlClient?
    private weak var renderer: GhosttyiOSRenderer?
    private var attachedPaneId: String?

    private var paneOutputTask: Task<Void, Never>?
    private var notificationTask: Task<Void, Never>?
    private var commandQueueTail: Task<Void, Never>?

    func connect(host: String, port: Int, user: String, password: String) async {
        await resetConnection()
        state = .connecting

        let manager = SSHConnectionManager()
        do {
            try await manager.connect(
                host: host,
                port: port,
                user: user,
                auth: .password(password)
            )
            sshManager = manager
            state = .connected
        } catch {
            await manager.disconnect()
            state = .disconnected(error)
        }
    }

    func attachSession(name: String, renderer: GhosttyiOSRenderer) async {
        registerRenderer(renderer)

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            state = .disconnected(SpikeCoordinatorError.emptySessionName)
            return
        }

        guard let sshManager else {
            state = .disconnected(SpikeCoordinatorError.notConnected)
            return
        }

        isAttachingSession = true
        defer { isAttachingSession = false }

        do {
            let command = "tmux -C new-session -A -s \(Self.shellQuote(trimmedName))"
            let channel = try await sshManager.openExecChannel(command: command)
            let client = TmuxControlClient(transport: SSHChannelTransport(channel: channel))

            sshChannel = channel
            tmuxClient = client
            await client.start()

            startPaneOutputTask(for: client)
            startNotificationTask(for: client)

            let paneResponse = try await runTmuxCommand("list-panes -F '#{pane_id}'")
            guard let paneId = paneResponse
                .split(whereSeparator: \.isNewline)
                .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                .first(where: { !$0.isEmpty })
            else {
                throw SpikeCoordinatorError.paneUnavailable
            }

            attachedPaneId = paneId
            try await refreshClientSizeIfNeeded()
            state = .attached(paneId: paneId)
        } catch {
            await transitionToDisconnected(error)
        }
    }

    func registerRenderer(_ renderer: GhosttyiOSRenderer) {
        self.renderer = renderer
        if case .attached = state {
            scheduleRefresh()
        }
    }

    func rendererDidResize(_ renderer: GhosttyiOSRenderer) {
        self.renderer = renderer
        if case .attached = state {
            scheduleRefresh()
        }
    }

    func sendInput(_ text: String) {
        guard let paneId = attachedPaneId else { return }
        let escapedText = Self.shellQuote(text)
        scheduleCommand("send-keys -l -t \(paneId) \(escapedText)")
    }

    func sendSpecialKey(_ key: String) {
        guard let paneId = attachedPaneId else { return }
        scheduleCommand("send-keys -t \(paneId) \(key)")
    }

    func presentDisconnected(error: Error?) {
        state = .disconnected(error)
    }

    private func startPaneOutputTask(for client: TmuxControlClient) {
        paneOutputTask?.cancel()
        paneOutputTask = Task { [weak self] in
            let paneOutput = await client.paneOutput
            for await event in paneOutput {
                await self?.applyPaneOutput(event)
            }
        }
    }

    private func startNotificationTask(for client: TmuxControlClient) {
        notificationTask?.cancel()
        notificationTask = Task { [weak self] in
            let notifications = await client.notifications
            for await notification in notifications {
                await self?.handleNotification(notification)
            }
        }
    }

    private func applyPaneOutput(_ event: (paneId: String, data: Data)) async {
        guard event.paneId == attachedPaneId else { return }
        renderer?.feedBytes(event.data)
    }

    private func handleNotification(_ notification: TmuxNotification) async {
        guard case .exit(let reason) = notification else { return }
        await transitionToDisconnected(SpikeCoordinatorError.tmuxExited(reason))
    }

    private func refreshClientSizeIfNeeded() async throws {
        guard let renderer else {
            throw SpikeCoordinatorError.rendererUnavailable
        }

        let gridSize = renderer.gridSize()
        guard gridSize.cols > 0, gridSize.rows > 0 else {
            return
        }

        _ = try await runTmuxCommand("refresh-client -C \(gridSize.cols),\(gridSize.rows)")
    }

    private func runTmuxCommand(_ command: String) async throws -> String {
        let previousTask = commandQueueTail
        let task = Task<String, Error> { @MainActor [weak self] in
            _ = await previousTask?.result

            guard let self, let tmuxClient = self.tmuxClient else {
                throw SpikeCoordinatorError.notConnected
            }

            return try await tmuxClient.sendCommand(command)
        }

        commandQueueTail = Task {
            _ = try? await task.value
        }

        return try await task.value
    }

    private func scheduleCommand(_ command: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = try? await self.runTmuxCommand(command)
        }
    }

    private func scheduleRefresh() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await self.refreshClientSizeIfNeeded()
        }
    }

    private func transitionToDisconnected(_ error: Error?) async {
        await resetConnection()
        state = .disconnected(error)
    }

    private func resetConnection() async {
        commandQueueTail?.cancel()
        commandQueueTail = nil

        paneOutputTask?.cancel()
        paneOutputTask = nil

        notificationTask?.cancel()
        notificationTask = nil

        attachedPaneId = nil
        isAttachingSession = false

        if let tmuxClient {
            self.tmuxClient = nil
            await tmuxClient.stop()
        }

        if let sshChannel {
            self.sshChannel = nil
            await sshChannel.close()
        }

        if let sshManager {
            self.sshManager = nil
            await sshManager.disconnect()
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

extension SpikeState {
    var isConnecting: Bool {
        if case .connecting = self {
            return true
        }
        return false
    }
}
