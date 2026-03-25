import SwiftUI
import GhosttyKit
import MoriRemoteProtocol

@main
struct MoriRemoteApp: App {
    @State private var ghosttyReady = false
    @State private var errorMessage: String?
    @Environment(\.scenePhase) private var scenePhase

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
                TerminalView()
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
                // App foregrounded — future: reconnect WebSocket
                GhosttyAppContext.shared.tick()
            case .background:
                // App backgrounded — future: detach and close WebSocket
                break
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }
}
