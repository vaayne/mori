import XCTest
@testable import MoriRemoteTerminal

final class MoriTmuxIsolationTests: XCTestCase {
    func testForbiddenServerCommandsAreNotInTerminalCoreSources() throws {
        // The behavioural controller uses only shadow-local selection plus the
        // input-only stale-mode cancellation. Keep this manifest explicit so a
        // future UI convenience action cannot smuggle shared mutations back in.
        let forbidden = ["refresh-client", "resize-pane -Z", "copy-mode -t", "requestZoomPane", "requestCopyMode", "setClientSize"]
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MoriRemoteTerminal")
        let source = try String(contentsOf: root.appendingPathComponent("Tmux/TmuxSessionController.swift"))
        for command in forbidden { XCTAssertFalse(source.contains(command), command) }
    }

    func testNarrowViewportDoesNotChangeTwoHundredColumnServerGrid() {
        // The initial control grid is a server attachment contract. A phone
        // viewport is renderer-local and cannot produce a tmux resize command.
        let server = TmuxControlViewport(columns: 200, rows: 60, pixelWidth: 2000, pixelHeight: 900)
        let narrowPhone = CGSize(width: 320, height: 480)
        XCTAssertEqual(server.columns, 200)
        XCTAssertEqual(GhosttyTerminalViewportCoordinator.normalized(narrowPhone), narrowPhone)
        XCTAssertFalse(TmuxSessionController.cancelStaleSharedInputMode.contains("resize"))
    }

    func testTopologyGridOwnsHydrationSizeNotPhoneViewport() throws {
        let pane = TmuxSessionController.PaneInfo(
            id: 10, windowID: 1, x: 0, y: 0, width: 200, height: 60, phase: .hydrating
        )
        let topology = TmuxSessionController.TopologySnapshot(
            sessionName: "main",
            windows: [.init(id: 1, name: "main", active: true, zoomed: false, width: 200, height: 60, activePaneID: 10)],
            panes: [pane], activeWindowID: 1
        )
        let size = try XCTUnwrap(TmuxSessionController.effectiveEngineSize(for: pane, in: topology))
        XCTAssertEqual(size.cols, 200)
        XCTAssertEqual(size.rows, 60)
        XCTAssertFalse(TmuxSessionController.cancelStaleSharedInputMode.contains("resize"))
    }

    func testStaleSharedModeCancellationIsInputOnly() {
        XCTAssertEqual(
            TmuxSessionController.cancelStaleSharedInputMode,
            "if-shell -F '#{pane_in_mode}' 'send-keys -X cancel' ''"
        )
    }
}
