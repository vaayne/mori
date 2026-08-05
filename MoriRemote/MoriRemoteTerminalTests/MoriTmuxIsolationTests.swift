import XCTest
@testable import MoriRemoteTerminal

final class MoriTmuxViewportOwnershipTests: XCTestCase {
    func testClientSizeRefreshUsesMeasuredGridWithoutHardCodedPhoneColumns() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MoriRemoteTerminal")
        let source = try String(contentsOf: root.appendingPathComponent("Tmux/TmuxSessionController.swift"))
        XCTAssertTrue(source.contains("refresh-client -C \\(cols)x\\(rows)"))
        XCTAssertFalse(source.contains("49 columns"))
    }

    func testViewportIsSeparateFromRendererLayoutButMayOwnSharedTmuxGrid() {
        let phoneViewport = TmuxControlViewport(columns: 83, rows: 44, pixelWidth: 0, pixelHeight: 0)
        XCTAssertEqual(phoneViewport.columns, 83)
        XCTAssertEqual(phoneViewport.rows, 44)
        XCTAssertEqual(GhosttyTerminalViewportCoordinator.normalized(CGSize(width: 320, height: 480)), CGSize(width: 320, height: 480))
    }

    func testTopologyGridStillOwnsHydrationSizeAfterSharedReflow() throws {
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
    }

    func testStaleSharedModeCancellationRemainsInputOnly() {
        XCTAssertEqual(
            TmuxSessionController.cancelStaleSharedInputMode,
            "if-shell -F '#{pane_in_mode}' 'send-keys -X cancel' ''"
        )
    }
}
