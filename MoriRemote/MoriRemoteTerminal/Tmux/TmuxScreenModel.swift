import Foundation
import GhosttyKit

/// Phase-1 composition seam. It owns an upstream session and screen adapter,
/// but deliberately does not construct a transport or touch Mori persistence.
@MainActor
final class TmuxScreenModel: ObservableObject {
    let terminalScreenAdapter = TmuxTerminalScreenAdapter()
    @Published private(set) var session: TmuxTerminalSession?
    @Published private(set) var startupFailure: String?

    init(
        app: ghostty_app_t,
        transport: any TmuxControlTransport,
        baseSurfaceConfig: @escaping () -> ghostty_terminal_surface_config_s,
        paneViewTheme: @escaping () -> TerminalTheme
    ) {
        let session = TmuxTerminalSession(
            app: app,
            transport: transport,
            baseSurfaceConfig: baseSurfaceConfig,
            paneViewTheme: paneViewTheme
        )
        self.session = session
        terminalScreenAdapter.activate(
            session: session,
            initialViewportHandler: { [weak session] size, scale in
                session?.updateViewportMetrics(size: size, scale: scale)
            },
            clientSizeHandler: { _ in },
            viewportStabilityHandler: { _ in }
        )
    }

    func stop() async {
        terminalScreenAdapter.invalidate()
        guard let session else { return }
        await session.shutdown()
        self.session = nil
    }
}
