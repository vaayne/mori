import Observation
import SwiftUI

@main
struct MoriRemoteApp: App {
    @State private var coordinator = ShellCoordinator()
    @State private var store = ServerStore()
    @State private var navigation = NavigationState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(coordinator)
                .environment(store)
                .environment(navigation)
        }
    }
}

/// Shared navigation state — replaces NotificationCenter for server selection.
@MainActor
@Observable
final class NavigationState {
    var activeServer: Server?
}

private struct RootView: View {
    @Environment(ShellCoordinator.self) private var coordinator
    @Environment(ServerStore.self) private var store
    @Environment(NavigationState.self) private var navigation

    var body: some View {
        Group {
            switch coordinator.state {
            case .disconnected, .connecting:
                ServerListView()
                    .onAppear { navigation.activeServer = nil }

            case .connected, .shell:
                if let server = navigation.activeServer {
                    TerminalScreen(
                        serverName: server.displayName,
                        onDisconnect: { disconnect() }
                    )
                } else {
                    ServerListView()
                        .onAppear { disconnect() }
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: coordinator.stateKey)
    }

    private func disconnect() {
        Task {
            await coordinator.disconnect()
        }
    }
}

extension String {
    static func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key)
    }
}
