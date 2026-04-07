import MoriTerminal
import Observation
import SwiftUI

@MainActor
@Observable
final class TerminalSessionHost {
    var showKeyBarCustomize = false
    var showTmuxCommands = false
    let accessoryBar = TerminalAccessoryBar()

    private weak var renderer: SwiftTermRenderer?
    private var hostedSessionState: HostedSessionState = .idle
    private var lastOpenRequest: ShellOpenRequest?

    func handleRendererReady(_ renderer: SwiftTermRenderer, coordinator: ShellCoordinator) {
        self.renderer = renderer
        coordinator.accessoryBar = accessoryBar
        accessoryBar.onCustomizeTapped = { [weak self] in
            self?.showKeyBarCustomize = true
        }
        accessoryBar.onTmuxMenuTapped = { [weak self] in
            self?.showTmuxCommands = true
        }

        renderer.initialLayoutHandler = { [weak self, weak renderer] _, _ in
            guard let self, let renderer else { return }
            self.openShellIfNeeded(with: renderer, coordinator: coordinator)
        }

        let size = renderer.gridSize()
        if size.cols > 0 && size.rows > 0 {
            openShellIfNeeded(with: renderer, coordinator: coordinator)
        }
    }

    func handleCoordinatorStateChange(_ state: ShellState, activeServerID: Server.ID?) {
        switch state {
        case .disconnected:
            hostedSessionState = .idle
            lastOpenRequest = nil
            renderer?.initialLayoutHandler = nil
            renderer = nil
            showKeyBarCustomize = false
            showTmuxCommands = false

        case .connecting:
            if hostedSessionState.serverID != activeServerID {
                hostedSessionState = .idle
                lastOpenRequest = nil
            }

        case .connected:
            hostedSessionState = activeServerID.map(HostedSessionState.waitingForShell) ?? .idle
            if lastOpenRequest?.serverID != activeServerID {
                lastOpenRequest = nil
            }

        case .shell:
            hostedSessionState = activeServerID.map(HostedSessionState.shellOpen) ?? .idle
            renderer?.activateKeyboard()
        }
    }

    private func openShellIfNeeded(with renderer: SwiftTermRenderer, coordinator: ShellCoordinator) {
        guard let activeServerID = coordinator.activeServer?.id else { return }

        let request = ShellOpenRequest(serverID: activeServerID, rendererID: ObjectIdentifier(renderer))
        guard lastOpenRequest != request else { return }

        switch coordinator.state {
        case .connected:
            if hostedSessionState.serverID != activeServerID {
                hostedSessionState = .waitingForShell(activeServerID)
            }
            lastOpenRequest = request
            renderer.initialLayoutHandler = nil
            Task { await coordinator.openShell(renderer: renderer) }

        case .shell:
            hostedSessionState = .shellOpen(activeServerID)
            lastOpenRequest = request
            renderer.initialLayoutHandler = nil
            Task { await coordinator.openShell(renderer: renderer) }

        case .connecting, .disconnected:
            break
        }
    }
}

private struct ShellOpenRequest: Equatable {
    let serverID: Server.ID
    let rendererID: ObjectIdentifier
}

private enum HostedSessionState: Equatable {
    case idle
    case waitingForShell(Server.ID)
    case shellOpen(Server.ID)

    var serverID: Server.ID? {
        switch self {
        case .idle:
            nil
        case .waitingForShell(let serverID), .shellOpen(let serverID):
            serverID
        }
    }
}
