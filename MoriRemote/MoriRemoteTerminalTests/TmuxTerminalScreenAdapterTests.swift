import GhosttyKit
import XCTest

@testable import MoriRemoteTerminal

@MainActor
final class TmuxTerminalScreenAdapterTests: XCTestCase {
    func testIdentityRegistryKeepsPaneRoundTripStable() {
        var registry = TmuxTerminalIdentityRegistry()
        let paneID = TmuxPaneID(41)

        let surfaceID = registry.surfaceID(for: paneID)

        XCTAssertEqual(registry.surfaceID(for: paneID), surfaceID)
        XCTAssertEqual(registry.paneID(for: surfaceID), paneID)
        XCTAssertNil(registry.paneID(for: UUID()))
    }

    func testIdentityRegistryKeepsWindowRoundTripStable() {
        var registry = TmuxTerminalIdentityRegistry()
        let windowID = TmuxWindowID(17)

        let surfaceID = registry.surfaceID(for: windowID)

        XCTAssertEqual(registry.surfaceID(for: windowID), surfaceID)
        XCTAssertEqual(registry.windowID(for: surfaceID), windowID)
        XCTAssertNil(registry.windowID(for: UUID()))
    }

    func testTopologyProjectionReflectsEmittedTopologyImmediately() async throws {
        let runtime = try GhosttyKitRuntime()
        let session = makeSession(runtime: runtime)
        let adapter = TmuxTerminalScreenAdapter()
        adapter.activate(
            session: session,
            initialViewportHandler: { _, _ in },
            viewportStabilityHandler: { _ in }
        )

        session.handleTopology(.init(
            sessionName: "fresh-test",
            windows: [
                window(id: 1, active: true, paneID: 10),
                window(id: 2, active: false, paneID: 20),
            ],
            panes: [pane(id: 10, windowID: 1), pane(id: 20, windowID: 2)],
            activeWindowID: 1
        ))

        let first = adapter.terminalInteractionProjection
        XCTAssertEqual(first.windowCount, 2)
        XCTAssertEqual(first.selectedWindowIndex, 0)
        XCTAssertEqual(first.paneCount, 1)

        session.handleTopology(.init(
            sessionName: "fresh-test",
            windows: [window(id: 1, active: true, paneID: 10)],
            panes: [pane(id: 10, windowID: 1)],
            activeWindowID: 1
        ))

        let second = adapter.terminalInteractionProjection
        XCTAssertEqual(second.windowCount, 1)
        XCTAssertEqual(second.selectedWindowIndex, 0)

        await session.shutdown()
    }

    private func makeSession(runtime: GhosttyKitRuntime) -> TmuxTerminalSession {
        TmuxTerminalSession(
            app: runtime.appHandleForTesting,
            transport: DeterministicTmuxControlTransport(chunks: []),
            baseSurfaceConfig: { runtime.makeTmuxBaseSurfaceConfig() },
            paneViewTheme: { .remuxDark },
            createPaneSurface: { _, _, _, _, _, _, _, completion in
                completion(.failure(.surfaceCreationFailed(
                    GHOSTTY_TERMINAL_SURFACE_RESULT_INVALID_INPUT
                )))
            }
        )
    }

    private func window(
        id: TmuxWindowID,
        active: Bool,
        paneID: TmuxPaneID?
    ) -> TmuxSessionController.WindowInfo {
        TmuxSessionController.WindowInfo(
            id: id,
            name: "",
            active: active,
            zoomed: true,
            width: 80,
            height: 24,
            activePaneID: paneID
        )
    }

    private func pane(
        id: TmuxPaneID,
        windowID: TmuxWindowID
    ) -> TmuxSessionController.PaneInfo {
        TmuxSessionController.PaneInfo(
            id: id,
            windowID: windowID,
            x: 0,
            y: 0,
            width: 80,
            height: 24,
            phase: .live
        )
    }
}
