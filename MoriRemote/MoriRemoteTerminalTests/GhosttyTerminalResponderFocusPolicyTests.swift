import XCTest
@testable import MoriRemoteTerminal

final class GhosttyTerminalResponderFocusPolicyTests: XCTestCase {
    func testTerminalOwnsSystemKeyboardWhenSelectedAndAvailable() {
        let policy = GhosttyTerminalResponderFocusPolicy(
            isSelected: true, keyboardMode: .system, keyboardOwner: .terminal,
            isInputAvailable: true, isTransientInputOwnerPresented: false
        )
        XCTAssertTrue(policy.isResponderEnabled)
        XCTAssertTrue(policy.wantsFirstResponder)
    }

    func testTransientInputOwnerSuspendsTerminalResponder() {
        let policy = GhosttyTerminalResponderFocusPolicy(
            isSelected: true, keyboardMode: .system, keyboardOwner: .terminal,
            isInputAvailable: true, isTransientInputOwnerPresented: true
        )
        XCTAssertFalse(policy.isResponderEnabled)
        XCTAssertFalse(policy.wantsFirstResponder)
    }

    func testHiddenKeyboardAndNonTerminalOwnerDoNotRequestFirstResponder() {
        XCTAssertFalse(GhosttyTerminalResponderFocusPolicy(
            isSelected: true, keyboardMode: .hidden, keyboardOwner: .none,
            isInputAvailable: true, isTransientInputOwnerPresented: false
        ).wantsFirstResponder)
        XCTAssertFalse(GhosttyTerminalResponderFocusPolicy(
            isSelected: true, keyboardMode: .system, keyboardOwner: .composer,
            isInputAvailable: true, isTransientInputOwnerPresented: false
        ).wantsFirstResponder)
    }
}
