import SwiftUI
import GhosttyKit
import MoriRemoteProtocol

/// Full-screen terminal view using ghostty's Remote backend.
/// Integrates PipeBridge for ghostty rendering with RelayClient for WebSocket data.
/// Includes mode toggle, detach button, and orientation-driven resize.
struct TerminalView: View {
    @State private var pipeBridge: PipeBridge?
    @State private var errorMessage: String?
    let relayClient: RelayClient
    let sessionName: String
    let mode: SessionMode
    let onToggleMode: () -> Void
    let onDetach: () -> Void
    let onResize: (UInt16, UInt16) -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let pipeBridge {
                GeometryReader { geometry in
                    RemoteTerminalRepresentable(pipeBridge: pipeBridge)
                        .ignoresSafeArea(.container, edges: .top)
                        .ignoresSafeArea(.keyboard)
                        .onChange(of: geometry.size) { _, newSize in
                            handleSizeChange(newSize)
                        }
                        .onAppear {
                            handleSizeChange(geometry.size)
                        }
                }
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

            // Floating controls overlay
            VStack {
                // Top bar: session name + detach
                HStack {
                    Text(sessionName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.5))
                        .clipShape(Capsule())

                    Spacer()

                    Button {
                        onDetach()
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(8)
                            .background(.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                // Bottom: mode toggle
                HStack {
                    Spacer()
                    ModeToggleButton(mode: mode, onToggle: onToggleMode)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 60) // Above input accessory bar
            }
        }
        .task {
            await initializePipeBridge()
        }
    }

    // MARK: - Size -> Resize

    /// Estimate terminal cols/rows from pixel size.
    /// Uses approximate character cell size (8pt wide, 16pt tall at 1x).
    private func handleSizeChange(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let cellWidth: CGFloat = 8.0
        let cellHeight: CGFloat = 16.0
        let cols = UInt16(max(size.width / cellWidth, 10))
        let rows = UInt16(max(size.height / cellHeight, 5))
        onResize(cols, rows)
    }

    // MARK: - Pipe Bridge Setup

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
