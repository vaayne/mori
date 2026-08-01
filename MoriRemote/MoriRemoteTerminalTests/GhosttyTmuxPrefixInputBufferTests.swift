import XCTest
@testable import MoriRemoteTerminal

final class GhosttyTmuxPrefixInputBufferTests: XCTestCase {
    func testNormalTextSubmitsImmediately() {
        var buffer = GhosttyTmuxPrefixInputBuffer()

        XCTAssertEqual(buffer.handleText("ls\r"), .submit("ls\r"))
    }

    func testPrefixArmsBufferWithFlushToken() {
        var buffer = GhosttyTmuxPrefixInputBuffer()

        XCTAssertEqual(
            buffer.handleText(GhosttyTmuxPrefixInputBuffer.defaultPrefixInput),
            .armPrefix(token: 1)
        )
    }

    func testPendingPrefixWithNormalTextSubmitsCombinedInputAndInvalidatesToken() {
        var buffer = GhosttyTmuxPrefixInputBuffer()
        XCTAssertEqual(
            buffer.handleText(GhosttyTmuxPrefixInputBuffer.defaultPrefixInput),
            .armPrefix(token: 1)
        )

        XCTAssertEqual(buffer.handleText("c"), .submit("\u{2}c"))
        XCTAssertNil(buffer.flushPendingInput(matching: 1))
    }

    func testPendingPrefixWithBracketRequestsCopyModeFallbackAndInvalidatesToken() {
        var buffer = GhosttyTmuxPrefixInputBuffer()
        XCTAssertEqual(
            buffer.handleText(GhosttyTmuxPrefixInputBuffer.defaultPrefixInput),
            .armPrefix(token: 1)
        )

        XCTAssertEqual(buffer.handleText("["), .enterCopyMode(fallbackInput: "\u{2}["))
        XCTAssertNil(buffer.flushPendingInput(matching: 1))
    }

    func testCurrentTokenFlushReturnsPendingPrefixAndClearsBuffer() {
        var buffer = GhosttyTmuxPrefixInputBuffer()
        XCTAssertEqual(
            buffer.handleText(GhosttyTmuxPrefixInputBuffer.defaultPrefixInput),
            .armPrefix(token: 1)
        )

        XCTAssertEqual(buffer.flushPendingInput(matching: 1), GhosttyTmuxPrefixInputBuffer.defaultPrefixInput)
        XCTAssertNil(buffer.flushPendingInput())
    }

    func testStaleTokenFlushReturnsNilWithoutClearingCurrentPendingPrefix() {
        var buffer = GhosttyTmuxPrefixInputBuffer()
        XCTAssertEqual(
            buffer.handleText(GhosttyTmuxPrefixInputBuffer.defaultPrefixInput),
            .armPrefix(token: 1)
        )
        XCTAssertEqual(buffer.flushPendingInput(matching: 1), GhosttyTmuxPrefixInputBuffer.defaultPrefixInput)
        XCTAssertEqual(
            buffer.handleText(GhosttyTmuxPrefixInputBuffer.defaultPrefixInput),
            .armPrefix(token: 3)
        )

        XCTAssertNil(buffer.flushPendingInput(matching: 1))
        XCTAssertEqual(buffer.flushPendingInput(matching: 3), GhosttyTmuxPrefixInputBuffer.defaultPrefixInput)
    }

    func testUnconditionalFlushReturnsPendingPrefixAndInvalidatesToken() {
        var buffer = GhosttyTmuxPrefixInputBuffer()
        XCTAssertEqual(
            buffer.handleText(GhosttyTmuxPrefixInputBuffer.defaultPrefixInput),
            .armPrefix(token: 1)
        )

        XCTAssertEqual(buffer.flushPendingInput(), GhosttyTmuxPrefixInputBuffer.defaultPrefixInput)
        XCTAssertNil(buffer.flushPendingInput(matching: 1))
    }

    func testSecondPrefixAfterConsumedStateArmsFreshToken() {
        var buffer = GhosttyTmuxPrefixInputBuffer()
        XCTAssertEqual(
            buffer.handleText(GhosttyTmuxPrefixInputBuffer.defaultPrefixInput),
            .armPrefix(token: 1)
        )
        XCTAssertEqual(buffer.handleText("c"), .submit("\u{2}c"))

        XCTAssertEqual(
            buffer.handleText(GhosttyTmuxPrefixInputBuffer.defaultPrefixInput),
            .armPrefix(token: 3)
        )
    }
}
