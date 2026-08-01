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

    func testAltLatchPrefixesTextWithEscapeAndClears() {
        var state = GhosttyModifierState()
        state.toggleAlt()

        XCTAssertEqual(state.apply(to: "b"), "\u{1B}b")
        XCTAssertFalse(state.isAltArmed)
    }

    func testControlAndAltLatchesComposeForText() {
        var state = GhosttyModifierState()
        state.toggleControl()
        state.toggleAlt()

        XCTAssertEqual(state.apply(to: "c"), "\u{1B}\u{03}")
        XCTAssertFalse(state.isControlArmed)
        XCTAssertFalse(state.isAltArmed)
    }

    func testAltLatchAddsModifierToKeyEventAndClearsBothLatches() {
        var state = GhosttyModifierState()
        state.toggleControl()
        state.toggleAlt()

        XCTAssertEqual(
            state.apply(to: GhosttySurfaceKeyEvent(keyCode: .arrowLeft)),
            GhosttySurfaceKeyEvent(keyCode: .arrowLeft, mods: [.ctrl, .alt])
        )
        XCTAssertFalse(state.isControlArmed)
        XCTAssertFalse(state.isAltArmed)
    }
}
