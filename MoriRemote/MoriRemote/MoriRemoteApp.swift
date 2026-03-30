import SwiftUI

@main
struct MoriRemoteApp: App {
    @State private var coordinator = ShellCoordinator()
    @State private var store = ServerStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(coordinator)
                .environment(store)
        }
    }
}

private struct RootView: View {
    @Environment(ShellCoordinator.self) private var coordinator

    var body: some View {
        Group {
            switch coordinator.state {
            case .disconnected, .connecting:
                ServerListView()

            case .connected, .shell:
                if let server = coordinator.activeServer {
                    TerminalScreen(
                        serverName: server.displayName,
                        onDisconnect: {
                            Task { await coordinator.disconnect() }
                        }
                    )
                } else {
                    ServerListView()
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: coordinator.state)
    }
}

extension String {
    static func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key)
    }
}
