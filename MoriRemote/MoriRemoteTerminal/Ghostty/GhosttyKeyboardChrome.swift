import SwiftUI

enum GhosttyKeyboardChromeMode: Equatable {
    case hidden
    case system

    var enablesSystemKeyboard: Bool { self == .system }
    func toggledKeyboard() -> Self { self == .hidden ? .system : .hidden }
    func applyingSystemKeyboardVisibility(_ isVisible: Bool) -> Self { isVisible ? .system : .hidden }
}

enum GhosttyKeyboardChromeSizing {
    static let dockButtonHeight: CGFloat = 38
    static let dockButtonWidth: CGFloat = 38
    static let compactDockButtonWidth: CGFloat = 35
    static let dockButtonCornerRadius: CGFloat = 17
    static let controlGroupVerticalPadding: CGFloat = 4
    static let baselineHeight = dockButtonHeight + (controlGroupVerticalPadding * 2)

    static func keyboardReplacementHeight(keyboardOverlapHeight: CGFloat, bottomSafeAreaHeight: CGFloat) -> CGFloat {
        guard keyboardOverlapHeight.isFinite, keyboardOverlapHeight > 0 else { return 0 }
        return ceil(max(0, keyboardOverlapHeight - max(0, bottomSafeAreaHeight)))
    }
}

struct GhosttyTerminalChromeStyle {
    let accent: Color
    let accentForeground: Color
    var selectedStroke: Color { accent.opacity(0.76) }
    static let ghosttyDefault = Self(accent: .accentColor, accentForeground: .white)
}

private struct GhosttyTerminalChromeStyleKey: EnvironmentKey {
    static let defaultValue = GhosttyTerminalChromeStyle.ghosttyDefault
}

extension EnvironmentValues {
    var ghosttyTerminalChromeStyle: GhosttyTerminalChromeStyle {
        get { self[GhosttyTerminalChromeStyleKey.self] }
        set { self[GhosttyTerminalChromeStyleKey.self] = newValue }
    }
}

enum GhosttyPhoneChromePalette { static let dock = Color.black }

/// Testable action boundary behind the remux-style menu chrome. Mori adds
/// categories and shared-mutation requests without importing account,
/// shortcut-store, or composer dependencies into the terminal module.
struct GhosttyKeyboardChromeActions {
    let showNavigator: () -> Void
    let toggleKeyboard: () -> Void
    let toggleControl: () -> Void
    let toggleAlt: () -> Void
    let requestSharedMutation: (MoriRemoteTerminalSharedMutation) -> Void
    let sendShortcut: (String) -> Bool
    let sendKey: (GhosttySurfaceKeyEvent) -> Bool

    func perform(_ action: Action) -> Bool {
        switch action {
        case .navigator: showNavigator(); return true
        case .keyboard: toggleKeyboard(); return true
        case .control: toggleControl(); return true
        case .alt: toggleAlt(); return true
        case .newWindow: requestSharedMutation(.newWindow); return true
        case .splitHorizontal: requestSharedMutation(.splitHorizontal); return true
        case .splitVertical: requestSharedMutation(.splitVertical); return true
        case .closePane: requestSharedMutation(.closePane); return true
        case .closeWindow: requestSharedMutation(.closeWindow); return true
        case .ctrlC: return sendShortcut("\u{03}")
        case .ctrlD: return sendShortcut("\u{04}")
        case .ctrlZ: return sendShortcut("\u{1A}")
        case .ctrlL: return sendShortcut("\u{0C}")
        case .ctrlA: return sendShortcut("\u{01}")
        case .ctrlE: return sendShortcut("\u{05}")
        case .ctrlR: return sendShortcut("\u{12}")
        case .ctrlU: return sendShortcut("\u{15}")
        case .ctrlK: return sendShortcut("\u{0B}")
        case .ctrlW: return sendShortcut("\u{17}")
        case .altB: return sendShortcut("\u{1B}b")
        case .altF: return sendShortcut("\u{1B}f")
        case .escape: return sendKey(.init(keyCode: .escape))
        case .tab: return sendKey(.init(keyCode: .tab))
        case .shiftTab: return sendKey(.init(keyCode: .tab, mods: .shift))
        case .arrowLeft: return sendKey(.init(keyCode: .arrowLeft))
        case .arrowUp: return sendKey(.init(keyCode: .arrowUp))
        case .arrowDown: return sendKey(.init(keyCode: .arrowDown))
        case .arrowRight: return sendKey(.init(keyCode: .arrowRight))
        case .home: return sendKey(.init(keyCode: .home))
        case .end: return sendKey(.init(keyCode: .end))
        case .pageUp: return sendKey(.init(keyCode: .pageUp))
        case .pageDown: return sendKey(.init(keyCode: .pageDown))
        case .questionMark:
            return sendKey(.init(keyCode: .slash, text: "?", mods: .shift, consumedMods: .shift, unshiftedCodepoint: 0x2F))
        case .slash:
            return sendKey(.init(keyCode: .slash, text: "/", unshiftedCodepoint: 0x2F))
        }
    }

    enum Action {
        case navigator, keyboard, control, alt
        case escape, tab, shiftTab, arrowLeft, arrowUp, arrowDown, arrowRight
        case home, end, pageUp, pageDown, questionMark, slash
        case ctrlC, ctrlD, ctrlZ, ctrlL, ctrlA, ctrlE, ctrlR, ctrlU, ctrlK, ctrlW, altB, altF
        case newWindow, splitHorizontal, splitVertical, closePane, closeWindow
    }
}

/// A single input accessory strip: four stable targets, no localized label
/// can distort the terminal viewport or move the keyboard control.
struct GhosttyKeyboardChrome: View {
    @Environment(\.ghosttyTerminalChromeStyle) private var chromeStyle
    @State private var showsKeypad = false

    let keyboardMode: GhosttyKeyboardChromeMode
    let isEnabled: Bool
    let isCompact: Bool
    let isControlArmed: Bool
    let isAltArmed: Bool
    let actions: GhosttyKeyboardChromeActions

    var body: some View {
        HStack(spacing: 0) {
            toolbarButton(
                "keyboard.badge.ellipsis",
                id: "terminal.keypad",
                label: String(localized: "Keypad"),
                active: isControlArmed || isAltArmed
            ) { showsKeypad = true }

            Menu {
                Section {
                    Button("New window") { _ = actions.perform(.newWindow) }
                    Button("Split right") { _ = actions.perform(.splitHorizontal) }
                    Button("Split down") { _ = actions.perform(.splitVertical) }
                }
                Section {
                    Button("Close pane", role: .destructive) { _ = actions.perform(.closePane) }
                    Button("Close window", role: .destructive) { _ = actions.perform(.closeWindow) }
                }
            } label: {
                toolbarIcon("terminal", active: false)
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel(String(localized: "tmux actions"))
            .accessibilityIdentifier("terminal.tmux-actions")
            .disabled(!isEnabled)

            toolbarButton(
                "rectangle.stack",
                id: "terminal.navigator",
                label: String(localized: "Navigator"),
                enabled: true
            ) { _ = actions.perform(.navigator) }

            toolbarButton(
                "keyboard",
                id: "terminal.keyboard",
                label: keyboardMode == .hidden ? String(localized: "Show keyboard") : String(localized: "Hide keyboard"),
                active: keyboardMode == .system
            ) { _ = actions.perform(.keyboard) }
        }
        .frame(height: 46)
        .padding(.horizontal, isCompact ? 8 : 16)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.7) }
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $showsKeypad) {
            GhosttyKeypadSheet(
                isControlArmed: isControlArmed,
                isAltArmed: isAltArmed,
                actions: actions
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func toolbarButton(
        _ systemName: String,
        id: String,
        label: String,
        enabled: Bool? = nil,
        active: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            toolbarIcon(systemName, active: active)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
        .disabled(!(enabled ?? isEnabled))
    }

    private func toolbarIcon(_ systemName: String, active: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(active ? chromeStyle.accent : Color.primary)
            .frame(width: 44, height: 38)
            .background(
                active ? chromeStyle.accent.opacity(0.15) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(Rectangle())
    }
}

extension View {
    func ghosttyTerminalChromePresentation(_ colorScheme: ColorScheme, chromeStyle: GhosttyTerminalChromeStyle) -> some View {
        preferredColorScheme(colorScheme).environment(\.ghosttyTerminalChromeStyle, chromeStyle)
    }
}
