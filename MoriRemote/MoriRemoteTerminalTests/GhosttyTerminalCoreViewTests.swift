import XCTest
import SwiftUI
@testable import MoriRemoteTerminal

@MainActor
final class GhosttyTerminalCoreViewTests: XCTestCase {
    func testCompositionRootConstructsWithDetachedAdapterAndNoSSH() {
        let adapter = TmuxTerminalScreenAdapter()
        let view = GhosttyTerminalCoreView(screen: adapter)

        // Construction is intentionally side-effect free: no transport, SSH
        // account, or persistence object is required before Phase 2 wiring.
        XCTAssertNotNil(view)
        XCTAssertEqual(adapter.stateTraceLabel, "released")
    }
}
