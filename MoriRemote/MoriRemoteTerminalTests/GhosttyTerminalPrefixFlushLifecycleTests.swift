import XCTest
@testable import MoriRemoteTerminal

final class GhosttyTerminalPrefixFlushLifecycleTests: XCTestCase {
    func testLonePrefixFlushesOnlyForItsScheduledToken() {
        var controller = GhosttyTerminalInputController()
        guard case .schedulePrefixFlush(let token) = controller.receiveText("\u{02}") else {
            return XCTFail("prefix must schedule delayed flush")
        }

        XCTAssertEqual(controller.flushPendingTmuxPrefixInput(matching: token), "\u{02}")
        XCTAssertNil(controller.flushPendingTmuxPrefixInput(matching: token))
    }

    func testStaleFlushTokenCannotSubmitAfterFollowupInputConsumesPrefix() {
        var controller = GhosttyTerminalInputController()
        guard case .schedulePrefixFlush(let stale) = controller.receiveText("\u{02}"),
              case .submit(let combined) = controller.receiveText("x")
        else { return XCTFail("follow-up input must consume pending prefix") }

        XCTAssertEqual(combined, "\u{02}x")
        XCTAssertNil(controller.flushPendingTmuxPrefixInput(matching: stale))
    }
}
