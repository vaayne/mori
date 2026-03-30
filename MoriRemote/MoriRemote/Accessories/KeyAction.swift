#if os(iOS)
import SwiftTerm
import UIKit

// MARK: - Key Action

/// Defines a key that can appear in the keyboard accessory bar.
/// Each action knows its display label, icon (if any), and the bytes/behavior it produces.
enum KeyAction: String, Codable, CaseIterable, Sendable {
    // Modifiers
    case esc
    case ctrl
    case alt
    case tab

    // Symbols
    case tilde      // ~
    case pipe       // |
    case slash      // /
    case dash       // -
    case underscore // _
    case equals     // =
    case backtick   // `
    case backslash  // \
    case bracketL   // [
    case bracketR   // ]
    case braceL     // {
    case braceR     // }
    case angleL     // <
    case angleR     // >
    case semicolon  // ;
    case singleQ    // '
    case doubleQ    // "
    case colon      // :

    // Navigation
    case left
    case down
    case up
    case right
    case home
    case end
    case pageUp
    case pageDown

    // Function keys
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12

    // Tmux shortcuts — mirrors Mori macOS menu actions
    case tmuxPrefix    // Ctrl+B (raw prefix)
    case tmuxNewTab    // Ctrl+B c — new window/tab
    case tmuxClosePane // Ctrl+B x — close pane (last pane closes tab)
    case tmuxNextTab   // Ctrl+B n — next window
    case tmuxPrevTab   // Ctrl+B p — previous window
    case tmuxSplitH    // Ctrl+B % — split right
    case tmuxSplitV    // Ctrl+B " — split down
    case tmuxNextPane  // Ctrl+B o — next pane
    case tmuxPrevPane  // Ctrl+B ; — previous pane
    case tmuxZoom      // Ctrl+B z — toggle pane zoom
    case tmuxDetach    // Ctrl+B d — detach session

    // Special
    case divider // visual separator, not a real key

    // MARK: - Display

    var label: String {
        switch self {
        case .esc:        return "esc"
        case .ctrl:       return "ctrl"
        case .alt:        return "alt"
        case .tab:        return "tab"
        case .tilde:      return "~"
        case .pipe:       return "|"
        case .slash:      return "/"
        case .dash:       return "-"
        case .underscore: return "_"
        case .equals:     return "="
        case .backtick:   return "`"
        case .backslash:  return "\\"
        case .bracketL:   return "["
        case .bracketR:   return "]"
        case .braceL:     return "{"
        case .braceR:     return "}"
        case .angleL:     return "<"
        case .angleR:     return ">"
        case .semicolon:  return ";"
        case .singleQ:    return "'"
        case .doubleQ:    return "\""
        case .colon:      return ":"
        case .left:       return "←"
        case .down:       return "↓"
        case .up:         return "↑"
        case .right:      return "→"
        case .home:       return "Home"
        case .end:        return "End"
        case .pageUp:     return "PgUp"
        case .pageDown:   return "PgDn"
        case .f1:         return "F1"
        case .f2:         return "F2"
        case .f3:         return "F3"
        case .f4:         return "F4"
        case .f5:         return "F5"
        case .f6:         return "F6"
        case .f7:         return "F7"
        case .f8:         return "F8"
        case .f9:         return "F9"
        case .f10:        return "F10"
        case .f11:        return "F11"
        case .f12:        return "F12"
        case .tmuxPrefix:    return "C-b"
        case .tmuxNewTab:    return "+tab"
        case .tmuxClosePane: return "close"
        case .tmuxNextTab:   return "tab›"
        case .tmuxPrevTab:   return "‹tab"
        case .tmuxSplitH:    return "split→"
        case .tmuxSplitV:    return "split↓"
        case .tmuxNextPane:  return "pane›"
        case .tmuxPrevPane:  return "‹pane"
        case .tmuxZoom:      return "zoom"
        case .tmuxDetach:    return "detach"
        case .divider:    return ""
        }
    }

    /// SF Symbol name, if the key uses an icon instead of text.
    var iconName: String? {
        switch self {
        case .left:  return "arrow.left"
        case .down:  return "arrow.down"
        case .up:    return "arrow.up"
        case .right: return "arrow.right"
        default:     return nil
        }
    }

    /// Whether this key is a modifier/special key (darker background).
    var isSpecial: Bool {
        switch self {
        case .esc, .ctrl, .alt, .tab: return true
        default: return false
        }
    }

    /// Whether this key is a tmux shortcut (accent-tinted).
    var isTmux: Bool {
        switch self {
        case .tmuxPrefix, .tmuxNewTab, .tmuxClosePane, .tmuxNextTab, .tmuxPrevTab,
             .tmuxSplitH, .tmuxSplitV, .tmuxNextPane, .tmuxPrevPane, .tmuxZoom, .tmuxDetach:
            return true
        default: return false
        }
    }

    /// Whether this key supports auto-repeat on long press.
    var supportsAutoRepeat: Bool {
        switch self {
        case .left, .down, .up, .right: return true
        default: return false
        }
    }

    /// Whether this is a toggle (sticky) key.
    var isToggle: Bool {
        self == .ctrl || self == .alt
    }

    // MARK: - Execution

    /// Send this key action to the terminal view.
    /// Returns `true` if the action was fully handled (non-toggle keys).
    /// Returns `false` for toggle keys that just flip state.
    @MainActor @discardableResult
    func execute(on terminalView: SwiftTerm.TerminalView) -> Bool {
        let terminal = terminalView.getTerminal()
        let appCursor = terminal.applicationCursor

        switch self {
        // Modifiers
        case .esc:
            terminalView.send(EscapeSequences.cmdEsc)
        case .ctrl:
            terminalView.controlModifier.toggle()
            return false
        case .alt:
            // Send ESC prefix for the next keystroke (meta key behavior)
            terminalView.send([0x1b])
        case .tab:
            terminalView.send(EscapeSequences.cmdTab)

        // Symbols — send as text
        case .tilde:      terminalView.send(txt: "~")
        case .pipe:       terminalView.send(txt: "|")
        case .slash:      terminalView.send(txt: "/")
        case .dash:       terminalView.send(txt: "-")
        case .underscore: terminalView.send(txt: "_")
        case .equals:     terminalView.send(txt: "=")
        case .backtick:   terminalView.send(txt: "`")
        case .backslash:  terminalView.send(txt: "\\")
        case .bracketL:   terminalView.send(txt: "[")
        case .bracketR:   terminalView.send(txt: "]")
        case .braceL:     terminalView.send(txt: "{")
        case .braceR:     terminalView.send(txt: "}")
        case .angleL:     terminalView.send(txt: "<")
        case .angleR:     terminalView.send(txt: ">")
        case .semicolon:  terminalView.send(txt: ";")
        case .singleQ:    terminalView.send(txt: "'")
        case .doubleQ:    terminalView.send(txt: "\"")
        case .colon:      terminalView.send(txt: ":")

        // Navigation
        case .left:
            terminalView.send(appCursor ? EscapeSequences.moveLeftApp : EscapeSequences.moveLeftNormal)
        case .down:
            terminalView.send(appCursor ? EscapeSequences.moveDownApp : EscapeSequences.moveDownNormal)
        case .up:
            terminalView.send(appCursor ? EscapeSequences.moveUpApp : EscapeSequences.moveUpNormal)
        case .right:
            terminalView.send(appCursor ? EscapeSequences.moveRightApp : EscapeSequences.moveRightNormal)
        case .home:
            terminalView.send(appCursor ? EscapeSequences.moveHomeApp : EscapeSequences.moveHomeNormal)
        case .end:
            terminalView.send(appCursor ? EscapeSequences.moveEndApp : EscapeSequences.moveEndNormal)
        case .pageUp:
            terminalView.send(EscapeSequences.cmdPageUp)
        case .pageDown:
            terminalView.send(EscapeSequences.cmdPageDown)

        // Function keys
        case .f1:  terminalView.send(EscapeSequences.cmdF[0])
        case .f2:  terminalView.send(EscapeSequences.cmdF[1])
        case .f3:  terminalView.send(EscapeSequences.cmdF[2])
        case .f4:  terminalView.send(EscapeSequences.cmdF[3])
        case .f5:  terminalView.send(EscapeSequences.cmdF[4])
        case .f6:  terminalView.send(EscapeSequences.cmdF[5])
        case .f7:  terminalView.send(EscapeSequences.cmdF[6])
        case .f8:  terminalView.send(EscapeSequences.cmdF[7])
        case .f9:  terminalView.send(EscapeSequences.cmdF[8])
        case .f10: terminalView.send(EscapeSequences.cmdF[9])
        case .f11: terminalView.send(EscapeSequences.cmdF[10])
        case .f12: terminalView.send(EscapeSequences.cmdF[11])

        // Tmux key actions — these are available in the customizable key bar.
        // The tmux popup menu uses real CLI commands instead (via TmuxCommand).
        // These remain for users who add individual tmux keys to their bar.
        case .tmuxPrefix:    terminalView.send([0x02])
        case .tmuxNewTab:    terminalView.send([0x02]); terminalView.send(txt: "c")
        case .tmuxClosePane: terminalView.send([0x02]); terminalView.send(txt: "x")
        case .tmuxNextTab:   terminalView.send([0x02]); terminalView.send(txt: "n")
        case .tmuxPrevTab:   terminalView.send([0x02]); terminalView.send(txt: "p")
        case .tmuxSplitH:    terminalView.send([0x02]); terminalView.send(txt: "%")
        case .tmuxSplitV:    terminalView.send([0x02]); terminalView.send(txt: "\"")
        case .tmuxNextPane:  terminalView.send([0x02]); terminalView.send(txt: "o")
        case .tmuxPrevPane:  terminalView.send([0x02]); terminalView.send(txt: ";")
        case .tmuxZoom:      terminalView.send([0x02]); terminalView.send(txt: "z")
        case .tmuxDetach:    terminalView.send([0x02]); terminalView.send(txt: "d")

        case .divider:
            break
        }
        return true
    }

    // MARK: - Categories (for palette UI)

    enum Category: String, CaseIterable {
        case modifiers = "Modifiers"
        case symbols = "Symbols"
        case navigation = "Navigation"
        case functionKeys = "Function Keys"
        case tmux = "Tmux Shortcuts"
    }

    var category: Category {
        switch self {
        case .esc, .ctrl, .alt, .tab:
            return .modifiers
        case .tilde, .pipe, .slash, .dash, .underscore, .equals, .backtick,
             .backslash, .bracketL, .bracketR, .braceL, .braceR,
             .angleL, .angleR, .semicolon, .singleQ, .doubleQ, .colon:
            return .symbols
        case .left, .down, .up, .right, .home, .end, .pageUp, .pageDown:
            return .navigation
        case .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12:
            return .functionKeys
        case .tmuxPrefix, .tmuxNewTab, .tmuxClosePane, .tmuxNextTab, .tmuxPrevTab,
             .tmuxSplitH, .tmuxSplitV, .tmuxNextPane, .tmuxPrevPane, .tmuxZoom, .tmuxDetach:
            return .tmux
        case .divider:
            return .symbols
        }
    }

    static func actions(for category: Category) -> [KeyAction] {
        allCases.filter { $0.category == category && $0 != .divider }
    }

    // MARK: - Default Layout

    // `.tmuxMenu` is a virtual key — it shows a popup with all tmux actions.
    // It's not a real KeyAction case but handled specially by KeyBarView.
    static let tmuxMenuPlaceholder = KeyAction.tmuxPrefix

    static let defaultLayout: [KeyAction] = [
        .esc, .ctrl, .tab,
        .divider,
        .tilde, .pipe, .slash, .dash,
        .divider,
        .left, .down, .up, .right,
    ]

}

// MARK: - Persistence

enum KeyBarLayout {
    private static let storageKey = "keybar_layout"
    private static let versionKey = "keybar_version"
    /// Bump this to force reset to new defaults on app update.
    private static let currentVersion = 3

    static func load() -> [KeyAction] {
        let savedVersion = UserDefaults.standard.integer(forKey: versionKey)
        if savedVersion < currentVersion {
            // New version — reset to updated defaults
            UserDefaults.standard.removeObject(forKey: storageKey)
            UserDefaults.standard.set(currentVersion, forKey: versionKey)
            return KeyAction.defaultLayout
        }
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let actions = try? JSONDecoder().decode([KeyAction].self, from: data)
        else {
            return KeyAction.defaultLayout
        }
        return actions
    }

    static func save(_ actions: [KeyAction]) {
        guard let data = try? JSONEncoder().encode(actions) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

#endif
