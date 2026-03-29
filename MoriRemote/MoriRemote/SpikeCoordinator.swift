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
    private var pendingOutputBuffer: [(paneId: String, data: Data)] = []

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
        // Prevent concurrent attach calls
        guard !isAttachingSession else { return }
        if case .attached = state { return }
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
            // PTY is allocated by the SSH channel, providing a proper terminal.
            // Use full path to avoid PATH issues in exec channels.
            let command = "/opt/homebrew/bin/tmux -C new-session -A -s \(Self.shellQuote(trimmedName))"
            let channel = try await sshManager.openExecChannel(command: command)
            let client = TmuxControlClient(transport: SSHChannelTransport(channel: channel))

            sshChannel = channel
            tmuxClient = client
            await client.start()
            await client.waitForReady()

            // Buffer output until pane ID is known, then start consumers
            startPaneOutputTask(for: client, buffered: true)
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

            // Flush buffered output now that pane ID is known
            for event in pendingOutputBuffer {
                if event.paneId == paneId {
                    self.renderer?.feedBytes(event.data)
                }
            }
            pendingOutputBuffer.removeAll()

            try await refreshClientSizeIfNeeded()

            // Capture existing pane content — %output only delivers new data,
            // so anything already on screen must be fetched explicitly.
            let captured = try await runTmuxCommand("capture-pane -t \(paneId) -p -e")
            if !captured.isEmpty, let data = (captured + "\n").data(using: .utf8) {
                self.renderer?.feedBytes(data)
            }

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

    private func startPaneOutputTask(for client: TmuxControlClient, buffered: Bool = false) {
        paneOutputTask?.cancel()
        paneOutputTask = Task { [weak self] in
            let paneOutput = await client.paneOutput
            for await event in paneOutput {
                guard let self else { return }
                if self.attachedPaneId != nil {
                    // Pane ID known — deliver directly
                    if event.paneId == self.attachedPaneId {
                        self.renderer?.feedBytes(event.data)
                    }
                } else {
                    // Pane ID not yet known — buffer
                    self.pendingOutputBuffer.append(event)
                }
            }
            // Stream ended — transport closed or tmux exited
            guard let self, !Task.isCancelled else { return }
            if case .attached = self.state {
                await self.transitionToDisconnected(
                    SpikeCoordinatorError.tmuxExited("pane output stream ended")
                )
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
            // Stream ended — transport closed
            guard let self, !Task.isCancelled else { return }
            if case .attached = self.state {
                await self.transitionToDisconnected(
                    SpikeCoordinatorError.tmuxExited("notification stream ended")
                )
            }
        }
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
            do {
                _ = try await self.runTmuxCommand(command)
            } catch {
                // Transport/SSH failure during background command → disconnect
                if case .attached = self.state {
                    await self.transitionToDisconnected(error)
                }
            }
        }
    }

    private func scheduleRefresh() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.refreshClientSizeIfNeeded()
            } catch {
                if case .attached = self.state {
                    await self.transitionToDisconnected(error)
                }
            }
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
        pendingOutputBuffer.removeAll()
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
