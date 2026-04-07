import SwiftUI

@main
struct MoriRemoteApp: App {
    @State private var coordinator = ShellCoordinator()
    @State private var store = ServerStore()
    @State private var regularWidthSelection = RegularWidthServerSelection()
    @State private var terminalSessionHost = TerminalSessionHost()

    var body: some Scene {
        WindowGroup {
            RootView(
                regularWidthSelection: regularWidthSelection,
                terminalSessionHost: terminalSessionHost
            )
            .environment(coordinator)
            .environment(store)
        }
    }
}

private struct RootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(ShellCoordinator.self) private var coordinator

    let regularWidthSelection: RegularWidthServerSelection
    let terminalSessionHost: TerminalSessionHost

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularWidthContent
            } else {
                compactContent
            }
        }
        .animation(.easeInOut(duration: 0.25), value: coordinator.state)
        .onAppear {
            terminalSessionHost.handleCoordinatorStateChange(
                coordinator.state,
                activeServerID: coordinator.activeServer?.id
            )
        }
        .onChange(of: coordinator.state) { _, newState in
            terminalSessionHost.handleCoordinatorStateChange(
                newState,
                activeServerID: coordinator.activeServer?.id
            )
        }
        .onChange(of: coordinator.activeServer?.id) { _, newServerID in
            regularWidthSelection.remember(coordinator.activeServer)
            terminalSessionHost.handleCoordinatorStateChange(
                coordinator.state,
                activeServerID: newServerID
            )
        }
    }

    @ViewBuilder
    private var compactContent: some View {
        switch coordinator.state {
        case .disconnected, .connecting:
            ServerListView()

        case .connected, .shell:
            terminalContent
        }
    }

    @ViewBuilder
    private var regularWidthContent: some View {
        switch coordinator.state {
        case .disconnected, .connecting:
            RegularWidthServerBrowserView(selection: regularWidthSelection)

        case .connected, .shell:
            terminalContent
        }
    }

    @ViewBuilder
    private var terminalContent: some View {
        if let server = coordinator.activeServer {
            TerminalScreen(
                sessionHost: terminalSessionHost,
                serverName: server.displayName,
                onDisconnect: returnToDisconnectedBrowser,
                onSwitchHost: returnToDisconnectedBrowser
            )
        } else if horizontalSizeClass == .regular {
            RegularWidthServerBrowserView(selection: regularWidthSelection)
        } else {
            ServerListView()
        }
    }

    private func returnToDisconnectedBrowser() {
        let activeServer = coordinator.activeServer
        regularWidthSelection.remember(activeServer)
        regularWidthSelection.select(activeServer)
        Task { await coordinator.disconnect() }
    }
}

extension String {
    static func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key)
    }
}
