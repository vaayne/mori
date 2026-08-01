import XCTest
@testable import MoriRemoteTerminal

final class GhosttyModifierStateTests: XCTestCase {
    func testControlLatchTransformsLetterAndClears() {
        var state = GhosttyModifierState()
        state.toggleControl()

        XCTAssertEqual(state.apply(to: "c"), "\u{03}")
        XCTAssertFalse(state.isControlArmed)
    }

    func testControlLatchTransformsBracketIntoEscape() {
        var state = GhosttyModifierState()
        state.toggleControl()

        XCTAssertEqual(state.apply(to: "["), "\u{1B}")
        XCTAssertFalse(state.isControlArmed)
    }

    func testControlLatchTransformsSpaceIntoNul() {
        var state = GhosttyModifierState()
        state.toggleControl()

        XCTAssertEqual(state.apply(to: " "), "\u{00}")
        XCTAssertFalse(state.isControlArmed)
    }

    func testControlLatchFallsBackToPlainTextAndClears() {
        var state = GhosttyModifierState()
        state.toggleControl()

        XCTAssertEqual(state.apply(to: "7"), "7")
        XCTAssertFalse(state.isControlArmed)
    }

    func testControlLatchAddsCtrlModifierToKeyEvent() {
        var state = GhosttyModifierState()
        state.toggleControl()
        let event = GhosttySurfaceKeyEvent(keyCode: .arrowUp)

        XCTAssertEqual(
            state.apply(to: event),
            GhosttySurfaceKeyEvent(keyCode: .arrowUp, mods: [.ctrl])
        )
        XCTAssertFalse(state.isControlArmed)
    }

}
