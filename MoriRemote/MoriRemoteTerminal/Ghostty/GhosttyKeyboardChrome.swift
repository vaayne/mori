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
    let showSessions: () -> Void
    let showLibrary: () -> Void
    let showWindows: () -> Void
    let showPanes: () -> Void
    let toggleKeyboard: () -> Void
    let toggleControl: () -> Void
    let toggleAlt: () -> Void
    let requestSharedMutation: (MoriRemoteTerminalSharedMutation) -> Void
    let sendKey: (GhosttySurfaceKeyEvent) -> Bool

    func perform(_ action: Action) -> Bool {
        switch action {
        case .sessions: showSessions(); return true
        case .library: showLibrary(); return true
        case .windows: showWindows(); return true
        case .panes: showPanes(); return true
        case .keyboard: toggleKeyboard(); return true
        case .control: toggleControl(); return true
        case .alt: toggleAlt(); return true
        case .newWindow: requestSharedMutation(.newWindow); return true
        case .splitHorizontal: requestSharedMutation(.splitHorizontal); return true
        case .splitVertical: requestSharedMutation(.splitVertical); return true
        case .closePane: requestSharedMutation(.closePane); return true
        case .closeWindow: requestSharedMutation(.closeWindow); return true
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
        case sessions, library, windows, panes, keyboard, control, alt
        case escape, tab, shiftTab, arrowLeft, arrowUp, arrowDown, arrowRight
        case home, end, pageUp, pageDown, questionMark, slash
        case newWindow, splitHorizontal, splitVertical, closePane, closeWindow
    }
}

/// Remux's compact three-group dock with Mori's terminal keys folded into
/// native menus. Keeping the keyboard at the upstream trailing position makes
/// its location stable while avoiding a horizontally scrolling toolbar.
struct GhosttyKeyboardChrome: View {
    @Environment(\.ghosttyTerminalChromeStyle) private var chromeStyle

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
            controlGroup { menuControls }
            controlGroup { navigationControls }
            controlGroup { inputControls }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }

    private var menuControls: some View {
        HStack(spacing: isCompact ? 1 : 2) {
            Menu {
                Button { _ = actions.perform(.control) } label: {
                    Label("Ctrl", systemImage: isControlArmed ? "checkmark" : "control")
                }
                Button { _ = actions.perform(.alt) } label: {
                    Label("Alt", systemImage: isAltArmed ? "checkmark" : "option")
                }
            } label: {
                menuLabel("control", active: isControlArmed || isAltArmed)
            }
            .accessibilityLabel(String(localized: "Modifiers"))
            .accessibilityIdentifier("terminal.modifiers")

            Menu {
                Section {
                    Button("Esc") { _ = actions.perform(.escape) }
                    Button("Tab") { _ = actions.perform(.tab) }
                    Button("Shift-Tab") { _ = actions.perform(.shiftTab) }
                }
                Section {
                    Button("←  Left") { _ = actions.perform(.arrowLeft) }
                    Button("↑  Up") { _ = actions.perform(.arrowUp) }
                    Button("↓  Down") { _ = actions.perform(.arrowDown) }
                    Button("→  Right") { _ = actions.perform(.arrowRight) }
                }
                Section {
                    Button("Home") { _ = actions.perform(.home) }
                    Button("End") { _ = actions.perform(.end) }
                    Button("Page Up") { _ = actions.perform(.pageUp) }
                    Button("Page Down") { _ = actions.perform(.pageDown) }
                }
                Section {
                    Button("?") { _ = actions.perform(.questionMark) }
                    Button("/") { _ = actions.perform(.slash) }
                }
            } label: {
                menuLabel("command")
            }
            .accessibilityLabel(String(localized: "Terminal keys"))
            .accessibilityIdentifier("terminal.keys")

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
                menuLabel("terminal")
            }
            .accessibilityLabel(String(localized: "tmux actions"))
            .accessibilityIdentifier("terminal.tmux-actions")
        }
        .disabled(!isEnabled)
    }

    private var navigationControls: some View {
        HStack(spacing: isCompact ? 1 : 2) {
            icon("rectangle.stack", id: "terminal.sessions", label: String(localized: "Sessions")) { actions.perform(.sessions) }
            icon("rectangle.on.rectangle", id: "terminal.windows", label: String(localized: "Windows"), enabled: windowCount > 0) { actions.perform(.windows) }
            icon("square.split.2x1", id: "terminal.panes", label: String(localized: "Panes"), enabled: paneCount > 0) { actions.perform(.panes) }
        }
    }

    private var inputControls: some View {
        HStack(spacing: isCompact ? 1 : 2) {
            icon("house", id: "terminal.home", label: String(localized: "Library"), enabled: true) { actions.perform(.library) }
            icon("keyboard", id: "terminal.keyboard", label: keyboardMode == .hidden ? String(localized: "Show keyboard") : String(localized: "Hide keyboard"), enabled: true, active: keyboardMode == .system) { actions.perform(.keyboard) }
        }
    }

    private func menuLabel(_ systemName: String, active: Bool = false) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .frame(width: dockButtonWidth, height: GhosttyKeyboardChromeSizing.dockButtonHeight)
            .foregroundStyle(active ? chromeStyle.accent : Color.primary)
            .background(active ? chromeStyle.accent.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: GhosttyKeyboardChromeSizing.dockButtonCornerRadius, style: .continuous))
            .contentShape(Rectangle())
    }

    private func controlGroup<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, isCompact ? 3 : 5)
            .padding(.vertical, GhosttyKeyboardChromeSizing.controlGroupVerticalPadding)
            .background(.thinMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75) }
    }

    private func icon(
        _ name: String,
        id: String,
        label: String,
        enabled: Bool = true,
        active: Bool = false,
        action: @escaping () -> Bool
    ) -> some View {
        Button { _ = action() } label: {
            Image(systemName: name).font(.system(size: 16.5, weight: .semibold))
        }
        .buttonStyle(ChromeButtonStyle(active: active, width: dockButtonWidth))
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
        .disabled((!isEnabled && id != "terminal.home") || !enabled)
    }

    private var dockButtonWidth: CGFloat {
        isCompact ? GhosttyKeyboardChromeSizing.compactDockButtonWidth : GhosttyKeyboardChromeSizing.dockButtonWidth
    }
}

private struct ChromeButtonStyle: ButtonStyle {
    let active: Bool
    let width: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: width, height: GhosttyKeyboardChromeSizing.dockButtonHeight)
            .foregroundStyle(active ? Color.accentColor : Color.primary)
            .background(active ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: GhosttyKeyboardChromeSizing.dockButtonCornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

extension View {
    func ghosttyTerminalChromePresentation(_ colorScheme: ColorScheme, chromeStyle: GhosttyTerminalChromeStyle) -> some View {
        preferredColorScheme(colorScheme).environment(\.ghosttyTerminalChromeStyle, chromeStyle)
    }
}
