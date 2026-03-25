import SwiftUI
import GhosttyKit
import MoriRemoteProtocol

@main
struct MoriRemoteApp: App {
    @State private var ghosttyReady = false
    @State private var errorMessage: String?
    @Environment(\.scenePhase) private var scenePhase

    /// Shared relay client for the app lifetime.
    @State private var relayClient = RelayClient()

    /// Track whether we were connected before backgrounding.
    @State private var wasConnectedBeforeBackground = false

    init() {
        let result = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
        if result == GHOSTTY_SUCCESS {
            _ghosttyReady = State(initialValue: true)
        } else {
            _errorMessage = State(initialValue: "ghostty_init failed with code \(result)")
        }
    }

    var body: some Scene {
        WindowGroup {
            if ghosttyReady {
                TerminalView(relayClient: relayClient)
                    .preferredColorScheme(.dark)
                    .statusBarHidden(true)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.yellow)
                    Text(errorMessage ?? "Unknown error")
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                GhosttyAppContext.shared.tick()
                // Reconnect if we were connected before backgrounding
                if wasConnectedBeforeBackground {
                    wasConnectedBeforeBackground = false
                    Task {
                        await relayClient.reconnect()
                    }
                }
            case .background:
                // Immediately detach and close WebSocket — no background keep-alive
                Task {
                    let currentState = await relayClient.state
                    if case .disconnected = currentState {
                        wasConnectedBeforeBackground = false
                    } else {
                        wasConnectedBeforeBackground = true
                        await relayClient.disconnect(reason: "app backgrounded")
                    }
                }
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }
}
