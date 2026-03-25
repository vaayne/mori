import SwiftUI
import GhosttyKit
import MoriRemoteProtocol

@main
struct MoriRemoteApp: App {
    @State private var ghosttyReady = false
    @State private var errorMessage: String?
    @Environment(\.scenePhase) private var scenePhase

    /// Central view model managing navigation, relay, and state.
    @State private var viewModel = AppViewModel()

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
                contentView
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
                if wasConnectedBeforeBackground {
                    wasConnectedBeforeBackground = false
                    viewModel.attemptReconnect()
                }
            case .background:
                let status = viewModel.connectionStatus
                if status != .disconnected {
                    wasConnectedBeforeBackground = true
                    viewModel.disconnectForBackground()
                } else {
                    wasConnectedBeforeBackground = false
                }
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        ZStack {
            switch viewModel.currentScreen {
            case .scanner:
                QRScannerView { url in
                    viewModel.handleScannedURL(url)
                }

            case .sessionList:
                SessionListView(
                    sessions: viewModel.sessions,
                    connectionStatus: viewModel.connectionStatus,
                    onAttach: { session in
                        viewModel.attachSession(session)
                    },
                    onRefresh: {
                        viewModel.requestSessionList()
                    },
                    onForgetDevice: {
                        viewModel.forgetDevice()
                    }
                )

            case .terminal(let sessionName):
                TerminalView(
                    relayClient: viewModel.relayClient,
                    sessionName: sessionName,
                    mode: viewModel.currentMode,
                    onToggleMode: { viewModel.toggleMode() },
                    onDetach: { viewModel.detachSession() },
                    onResize: { cols, rows in
                        viewModel.sendResize(cols: cols, rows: rows)
                    }
                )
            }

            // Connection status overlay
            VStack {
                ConnectionStatusView(status: viewModel.connectionStatus)
                    .padding(.top, 8)
                Spacer()
            }
            .animation(.easeInOut(duration: 0.3), value: viewModel.connectionStatus)
        }
    }
}
