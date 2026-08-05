import XCTest
@testable import MoriRemoteTerminal

final class GhosttyKeyboardChromeModeTests: XCTestCase {
    func testRemuxDockSizingRetainsReferenceGeometry() {
        XCTAssertEqual(GhosttyKeyboardChromeSizing.dockButtonWidth, 38)
        XCTAssertEqual(GhosttyKeyboardChromeSizing.dockButtonHeight, 38)
        XCTAssertEqual(GhosttyKeyboardChromeSizing.dockButtonCornerRadius, 17)
        XCTAssertEqual(GhosttyKeyboardChromeSizing.controlGroupVerticalPadding, 4)
        XCTAssertEqual(GhosttyKeyboardChromeSizing.regularControlGroupSpacing, 10)
        XCTAssertEqual(GhosttyKeyboardChromeSizing.dockContentHorizontalPadding, 12)
        XCTAssertEqual(GhosttyKeyboardChromeSizing.dockContentVerticalPadding, 4)
    }

    func testKeyboardToggleShowsSystemKeyboardFromHiddenMode() {
        XCTAssertEqual(GhosttyKeyboardChromeMode.hidden.toggledKeyboard(), .system)
    }

    func testKeyboardToggleHidesSystemKeyboard() {
        XCTAssertEqual(GhosttyKeyboardChromeMode.system.toggledKeyboard(), .hidden)
    }

    func testSystemKeyboardVisibilitySyncsHiddenAndSystemModes() {
        XCTAssertEqual(
            GhosttyKeyboardChromeMode.hidden.applyingSystemKeyboardVisibility(true),
            .system
        )
        XCTAssertEqual(
            GhosttyKeyboardChromeMode.system.applyingSystemKeyboardVisibility(false),
            .hidden
        )
    }

    func testKeyboardModeOnlyControlsKeyboardIntent() {
        XCTAssertFalse(GhosttyKeyboardChromeMode.hidden.enablesSystemKeyboard)
        XCTAssertTrue(GhosttyKeyboardChromeMode.system.enablesSystemKeyboard)
    }
}
