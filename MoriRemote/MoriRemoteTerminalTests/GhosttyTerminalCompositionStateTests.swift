import CoreGraphics
import XCTest
@testable import MoriRemoteTerminal

final class GhosttyTerminalCompositionStateTests: XCTestCase {
    func testKeyboardShowAndDismissPreserveViewportUntilCompletion() {
        var state = GhosttyTerminalCompositionState()
        _ = state.reconcileViewport(CGSize(width: 390, height: 700))
        state.inputCoordinator.showSystemKeyboard(isInputAvailable: true)

        let request = state.applyKeyboardVisibility(
            frameEnd: CGRect(x: 0, y: 400, width: 390, height: 444),
            screenBounds: CGRect(x: 0, y: 0, width: 390, height: 844),
            animationDuration: 0.25
        )
        XCTAssertEqual(state.keyboardOverlapHeight, 444)
        XCTAssertEqual(request?.target, .shown)
        let begin = state.beginKeyboardTransition(request!)
        XCTAssertTrue(state.viewportCoordinator.isKeyboardTransitionActive)
        XCTAssertEqual(state.viewportCoordinator.effectiveSize(liveSize: CGSize(width: 390, height: 400)), CGSize(width: 390, height: 700))
        XCTAssertNotNil(state.completeKeyboardTransition(token: begin.fallbackToken))
        XCTAssertFalse(state.viewportCoordinator.isKeyboardTransitionActive)

        state.inputCoordinator.dismissKeyboard()
        let hide = state.applyKeyboardVisibility(
            frameEnd: CGRect(x: 0, y: 844, width: 390, height: 0),
            screenBounds: CGRect(x: 0, y: 0, width: 390, height: 844),
            animationDuration: 0.25
        )
        XCTAssertEqual(state.keyboardOverlapHeight, 0)
        XCTAssertEqual(hide?.target, .hidden)
    }
}
