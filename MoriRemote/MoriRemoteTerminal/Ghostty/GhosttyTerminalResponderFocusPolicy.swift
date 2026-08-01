import Foundation

struct GhosttyTerminalResponderFocusPolicy: Equatable {
    let isSelected: Bool
    let keyboardMode: GhosttyKeyboardChromeMode
    let keyboardOwner: GhosttyKeyboardOwner
    let isInputAvailable: Bool
    let isTransientInputOwnerPresented: Bool

    var isResponderEnabled: Bool {
        isInputAvailable
            && !isTransientInputOwnerPresented
    }

    var wantsFirstResponder: Bool {
        isSelected
            && keyboardMode.enablesSystemKeyboard
            && keyboardOwner == .terminal
            && isResponderEnabled
    }
}
