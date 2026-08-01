import SwiftUI

/// Upstream-compatible keyboard intent. The Phase-1 bar intentionally omits
/// composer and shortcut-marketplace actions, not terminal controls.
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

/// The semantic, testable action boundary behind the retained upstream dock.
/// It has no account, composer, or shortcut-store dependency.
struct GhosttyKeyboardChromeActions {
    let showSessions: () -> Void
    let showWindows: () -> Void
    let showPanes: () -> Void
    let toggleKeyboard: () -> Void
    let toggleControl: () -> Void
    let toggleAlt: () -> Void
    let sendKey: (GhosttySurfaceKeyEvent) -> Bool

    func perform(_ action: Action) -> Bool {
        switch action {
        case .sessions: showSessions(); return true
        case .windows: showWindows(); return true
        case .panes: showPanes(); return true
        case .keyboard: toggleKeyboard(); return true
        case .control: toggleControl(); return true
        case .alt: toggleAlt(); return true
        case .escape: return sendKey(.init(keyCode: .escape))
        case .tab: return sendKey(.init(keyCode: .tab))
        case .shiftTab: return sendKey(.init(keyCode: .tab, mods: .shift))
        case .arrowLeft: return sendKey(.init(keyCode: .arrowLeft))
        case .arrowUp: return sendKey(.init(keyCode: .arrowUp))
        case .arrowDown: return sendKey(.init(keyCode: .arrowDown))
        case .arrowRight: return sendKey(.init(keyCode: .arrowRight))
        case .questionMark:
            return sendKey(.init(keyCode: .slash, text: "?", mods: .shift, consumedMods: .shift, unshiftedCodepoint: 0x2F))
        case .slash:
            return sendKey(.init(keyCode: .slash, text: "/", unshiftedCodepoint: 0x2F))
        }
    }

    enum Action {
        case sessions, windows, panes, keyboard, control, alt, escape, tab, shiftTab
        case arrowLeft, arrowUp, arrowDown, arrowRight, questionMark, slash
    }
}

/// The retained terminal portion of remux's keyboard chrome. It keeps Ctrl,
/// Esc, Tab, session/window/pane selectors, and system-keyboard control.
struct GhosttyKeyboardChrome: View {
    let keyboardMode: GhosttyKeyboardChromeMode
    let isEnabled: Bool
    let isCompact: Bool
    let isControlArmed: Bool
    let isAltArmed: Bool
    let windowCount: Int
    let paneCount: Int
    let actions: GhosttyKeyboardChromeActions

    var body: some View {
        HStack(spacing: isCompact ? 6 : 10) {
            group {
                icon("keyboard", id: "terminal.keyboard", label: keyboardMode == .hidden ? "Show keyboard" : "Hide keyboard") { actions.perform(.keyboard) }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: isCompact ? 6 : 10) {
                    group {
                        key("esc", id: "terminal.esc") { actions.perform(.escape) }
                        key("tab", id: "terminal.tab") { actions.perform(.tab) }
                        key("ctrl", id: "terminal.ctrl", active: isControlArmed) { actions.perform(.control) }
                        key("alt", id: "terminal.alt", active: isAltArmed) { actions.perform(.alt) }
                    }
                    group {
                        key("←", id: "terminal.left", label: "Left arrow") { actions.perform(.arrowLeft) }
                        key("↑", id: "terminal.up", label: "Up arrow") { actions.perform(.arrowUp) }
                        key("↓", id: "terminal.down", label: "Down arrow") { actions.perform(.arrowDown) }
                        key("→", id: "terminal.right", label: "Right arrow") { actions.perform(.arrowRight) }
                    }
                    group {
                        key("⇧tab", id: "terminal.shift-tab", label: "Shift Tab", width: 54) { actions.perform(.shiftTab) }
                        key("?", id: "terminal.question-mark") { actions.perform(.questionMark) }
                        key("/", id: "terminal.slash") { actions.perform(.slash) }
                    }
                    group {
                        icon("rectangle.stack", id: "terminal.sessions", label: "Sessions") { actions.perform(.sessions) }
                        icon("rectangle.on.rectangle", id: "terminal.windows", label: "Windows", enabled: windowCount > 0) { actions.perform(.windows) }
                        icon("square.split.2x1", id: "terminal.panes", label: "Panes", enabled: paneCount > 0) { actions.perform(.panes) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 2, content: content)
            .padding(4)
            .background(.thinMaterial, in: Capsule())
    }

    private func key(
        _ title: String,
        id: String,
        label: String? = nil,
        active: Bool = false,
        width: CGFloat = GhosttyKeyboardChromeSizing.dockButtonWidth,
        action: @escaping () -> Bool
    ) -> some View {
        Button { _ = action() } label: { Text(title).font(.system(size: 12, weight: .semibold)) }
            .buttonStyle(ChromeButtonStyle(active: active, width: width))
            .accessibilityLabel(label ?? title)
            .accessibilityIdentifier(id)
            .disabled(!isEnabled)
    }

    private func icon(_ name: String, id: String, label: String, enabled: Bool = true, action: @escaping () -> Bool) -> some View {
        Button { _ = action() } label: { Image(systemName: name).font(.system(size: 16, weight: .semibold)) }
            .buttonStyle(ChromeButtonStyle(active: id == "terminal.keyboard" && keyboardMode == .system, width: GhosttyKeyboardChromeSizing.dockButtonWidth))
            .accessibilityLabel(label)
            .accessibilityIdentifier(id)
            .disabled(!isEnabled || !enabled)
    }
}

private struct ChromeButtonStyle: ButtonStyle {
    let active: Bool
    let width: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: width, height: GhosttyKeyboardChromeSizing.dockButtonHeight)
            .foregroundStyle(active ? Color.accentColor : Color.primary)
            .background(active ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: GhosttyKeyboardChromeSizing.dockButtonCornerRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

extension View {
    func ghosttyTerminalChromePresentation(_ colorScheme: ColorScheme, chromeStyle: GhosttyTerminalChromeStyle) -> some View {
        preferredColorScheme(colorScheme).environment(\.ghosttyTerminalChromeStyle, chromeStyle)
    }
}
