import Observation
import SwiftUI

@main
struct MoriRemoteApp: App {
    @State private var coordinator = SpikeCoordinator()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(coordinator)
        }
    }
}

private struct RootView: View {
    @Environment(SpikeCoordinator.self) private var coordinator

    @State private var sessionName = "main"
    @State private var activeSessionName: String?

    var body: some View {
        Group {
            switch coordinator.state {
            case .disconnected, .connecting:
                ConnectView()
                    .onAppear {
                        activeSessionName = nil
                    }
            case .connected, .attached:
                if let activeSessionName {
                    TerminalScreen(sessionName: activeSessionName)
                } else {
                    SessionAttachView(
                        sessionName: $sessionName,
                        onAttach: {
                            activeSessionName = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    )
                }
            }
        }
    }
}

private struct SessionAttachView: View {
    @Binding var sessionName: String
    let onAttach: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Session Name", text: $sessionName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Button("Attach Session") {
                        onAttach()
                    }
                    .disabled(sessionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Session")
        }
    }
}

private struct TerminalScreen: View {
    @Environment(SpikeCoordinator.self) private var coordinator

    let sessionName: String

    @State private var attachStarted = false

    var body: some View {
        TerminalView(
            onRendererReady: { renderer in
                coordinator.registerRenderer(renderer)

                guard !attachStarted else { return }
                attachStarted = true

                Task {
                    await coordinator.attachSession(name: sessionName, renderer: renderer)
                }
            }
        )
        .ignoresSafeArea(edges: .bottom)
        .background(Color.black)
        .overlay {
            if coordinator.isAttachingSession || !coordinator.isTerminalAttached {
                ProgressView("Attaching session...")
                    .padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

private extension SpikeCoordinator {
    var isTerminalAttached: Bool {
        if case .attached = state {
            return true
        }
        return false
    }
}

extension String {
    static func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key)
    }
}
