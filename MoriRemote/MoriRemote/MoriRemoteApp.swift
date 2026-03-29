import Observation
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
    @Environment(ServerStore.self) private var store

    /// The server we're currently connecting/connected to.
    @State private var activeServer: Server?

    var body: some View {
        Group {
            switch coordinator.state {
            case .disconnected, .connecting:
                ServerListView()
                    .onAppear { activeServer = nil }

            case .connected, .shell:
                if let server = activeServer {
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
        .onReceive(NotificationCenter.default.publisher(for: .serverSelected)) { note in
            if let server = note.object as? ServerBox {
                activeServer = server.value
            }
        }
    }

    private func disconnect() {
        Task {
            await coordinator.disconnect()
        }
    }
}

// Notification-based bridge so ServerListView can set activeServer before connect.
extension Notification.Name {
    static let serverSelected = Notification.Name("serverSelected")
}

/// Box to pass Server through NotificationCenter (which needs AnyObject or uses `object`).
final class ServerBox: @unchecked Sendable {
    let value: Server
    init(_ value: Server) { self.value = value }
}

extension String {
    static func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key)
    }
}
