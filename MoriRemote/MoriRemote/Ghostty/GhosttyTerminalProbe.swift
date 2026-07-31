import SwiftUI
import Observation

#if DEBUG
/// Credential-free integration route. The terminal pixels below are the native
/// Ghostty UIView fed by the same tmux controller/link used in production.
struct GhosttyTerminalProbe: View {
    @State private var model = ProbeModel()
    var body: some View {
        VStack(spacing: 8) {
            if let surface = model.surface {
                TmuxPaneSurfaceView(surface: surface)
            } else if model.didTimeOut {
                ContentUnavailableView("Ghostty renderer failed", systemImage: "exclamationmark.triangle", description: Text(model.status))
            } else {
                ProgressView(String(localized: "Ghostty terminal probe loading"))
            }
            Text(model.status).font(.caption).foregroundStyle(model.didTimeOut ? .red : .secondary)
        }
        .padding()
        .accessibilityIdentifier("ghostty-terminal-probe")
        .task { await model.start() }
        .onDisappear { Task { await model.stop() } }
    }
}

@MainActor
@Observable private final class ProbeModel {
    var surface: TmuxPaneSurface?
    var status = String(localized: "Starting Ghostty tmux transcript…")
    var didTimeOut = false
    private var ghostty: GhosttyKitRuntime?
    private var timeoutTask: Task<Void, Never>?
    private var runtime: GhosttyTmuxRuntime?

    func start() async {
        guard runtime == nil else { return }
        do {
            let ghostty = try GhosttyKitRuntime()
            let pane = "%0;83;44;0;0;1;;;;0;4294967295;4294967295;0;1;0;0;0;0;0;0;0;0;;;0;0;43;8,16\n"
            let window = "$42 @0 1 %0 83 44 b7dd,83x44,0,0,0 b7dd,83x44,0,0,0 probe\n"
            // This startup transcript is the upstream deterministic fixture.
            let transcript = "%begin 1 1 0\n%end 1 1 0\n%session-changed $42 main\n" + "%begin 2 2 1\n3.1\n%end 2 2 1\n" + "%begin 3 3 1\n%end 3 3 1\n" + "%begin 4 4 1\n\(window)%end 4 4 1\n" + "%begin 5 5 1\n\(pane)%end 5 5 1\n" + (6...9).map { "%begin \($0) \($0) 1\n%end \($0) \($0) 1\n" }.joined()
            let runtime = GhosttyTmuxRuntime(app: ghostty.appHandle, transport: DeterministicTmuxControlTransport(transcript: [transcript]))
            runtime.onSurface = { [weak self, weak runtime] surface in
                self?.timeoutTask?.cancel()
                self?.surface = surface
                runtime?.feedDeterministicOutput("%output %0 MoriRemote Ghostty transcript\\015\\012$ \n")
                self?.status = String(localized: "Ghostty transcript fed; waiting for native draw…")
                Task { @MainActor [weak self, weak surface] in
                    guard let surface else { return }
                    for _ in 0..<20 {
                        if surface.drawCount >= 3 {
                            self?.status = String(localized: "Ghostty rendered deterministic tmux transcript")
                            return
                        }
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    self?.didTimeOut = true
                    self?.status = String(format: String(localized: "Ghostty renderer did not draw transcript: %@"), surface.rendererDiagnostics())
                }
            }
            runtime.onState = { [weak self] state in self?.status = String(format: String(localized: "Ghostty tmux: %@"), String(describing: state)) }
            self.ghostty = ghostty; self.runtime = runtime
            try await runtime.start(columns: 83, rows: 44)
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self else { return }
                guard let surface = self.surface else {
                    self.didTimeOut = true
                    self.status = String(localized: "No live Ghostty terminal surface arrived within 5 seconds.")
                    return
                }
                guard surface.drawCount < 3 else { return }
                self.didTimeOut = true
                self.status = String(format: String(localized: "Ghostty renderer timed out: %@"), surface.rendererDiagnostics())
            }
        } catch {
            didTimeOut = true
            status = String(format: String(localized: "Ghostty probe failed: %@"), String(describing: error))
        }
    }
    func stop() async { timeoutTask?.cancel(); timeoutTask = nil; await runtime?.stop(); runtime = nil; ghostty = nil; surface = nil }
}
#endif
