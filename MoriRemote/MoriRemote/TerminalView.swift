import SwiftUI
import GhosttyKit
import MoriRemoteProtocol

/// Full-screen terminal view using ghostty's Remote backend.
/// Integrates PipeBridge for ghostty rendering with RelayClient for WebSocket data.
struct TerminalView: View {
    @State private var pipeBridge: PipeBridge?
    @State private var errorMessage: String?
    let relayClient: RelayClient

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let pipeBridge {
                RemoteTerminalRepresentable(pipeBridge: pipeBridge)
                    .ignoresSafeArea(.container, edges: .top)
                    .ignoresSafeArea(.keyboard)
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.yellow)
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else {
                ProgressView("Initializing terminal...")
                    .foregroundStyle(.white)
            }
        }
        .task {
            await initializePipeBridge()
        }
    }

    private func initializePipeBridge() async {
        do {
            let bridge = try PipeBridge()

            // Wire PipeBridge -> RelayClient: user input from ghostty sent to relay
            let client = relayClient
            await bridge.setOnInputFromGhostty { data in
                try? await client.sendTerminalData(data)
            }

            // Wire RelayClient -> PipeBridge: terminal data from relay written to ghostty
            await client.setOnTerminalData { data in
                await bridge.writeToTerminal(data)
            }

            await bridge.start()

            self.pipeBridge = bridge
        } catch {
            self.errorMessage = "Failed to create pipe bridge: \(error)"
        }
    }
}

// MARK: - UIViewRepresentable

/// SwiftUI wrapper around `GhosttyRemoteSurfaceView`.
/// Creates the ghostty surface with Remote backend fd pair from the pipe bridge.
private struct RemoteTerminalRepresentable: UIViewRepresentable {
    let pipeBridge: PipeBridge

    func makeUIView(context: Context) -> UIView {
        guard let app = GhosttyAppContext.shared.app else {
            return makeErrorLabel("ghostty app not initialized")
        }

        do {
            let surfaceView = try GhosttyRemoteSurfaceView(app: app, pipeBridge: pipeBridge)
            surfaceView.setFocus(true)
            return surfaceView
        } catch {
            return makeErrorLabel("Surface creation failed: \(error)")
        }
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Update size on layout changes
        if let surfaceView = uiView as? GhosttyRemoteSurfaceView {
            surfaceView.setNeedsLayout()
        }
    }

    private func makeErrorLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = .red
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }
}
