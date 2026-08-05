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
    static let regularControlGroupSpacing: CGFloat = 10
    static let compactControlGroupSpacing: CGFloat = 6
    static let dockContentHorizontalPadding: CGFloat = 12
    static let dockContentVerticalPadding: CGFloat = 4
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
        case .sessions, .windows, .panes: showNavigator(); return true
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
        // The app currently exposes one Navigator sheet for all three scopes.
        // Keep the dock's intended destinations distinct here so their mapping
        // can change without reshaping its view hierarchy.
        case sessions, windows, panes, keyboard, control, alt
        case escape, tab, shiftTab, arrowLeft, arrowUp, arrowDown, arrowRight
        case home, end, pageUp, pageDown, questionMark, slash
        case ctrlC, ctrlD, ctrlZ, ctrlL, ctrlA, ctrlE, ctrlR, ctrlU, ctrlK, ctrlW, altB, altF
        case newWindow, splitHorizontal, splitVertical, closePane, closeWindow
    }
}

/// The remux-derived terminal dock. Its action boundary deliberately retains
/// Mori-only keypad, image, and shared-mutation actions even though this dock
/// only presents the original terminal controls.
struct GhosttyKeyboardChrome: View {
    private enum PresentedSheet: String, Identifiable {
        case keypad, image
        var id: Self { self }
    }

    @Environment(\.ghosttyTerminalChromeStyle) private var chromeStyle
    @State private var presentedSheet: PresentedSheet?

    let keyboardMode: GhosttyKeyboardChromeMode
    let isEnabled: Bool
    let isCompact: Bool
    let isControlArmed: Bool
    let isAltArmed: Bool
    let imageUploader: MoriRemoteTerminalImageUploader?
    let insertImagePath: (String) -> Bool
    let onImagePresentationChange: (Bool) -> Void
    let actions: GhosttyKeyboardChromeActions

    var body: some View {
        HStack(spacing: isCompact ? GhosttyKeyboardChromeSizing.compactControlGroupSpacing : GhosttyKeyboardChromeSizing.regularControlGroupSpacing) {
            controlGroup {
                key("ctrl", id: "terminal.ctrl", active: isControlArmed) { actions.perform(.control) }
                key("esc", id: "terminal.esc") { actions.perform(.escape) }
                key("tab", id: "terminal.tab") { actions.perform(.tab) }
            }
            controlGroup {
                icon("rectangle.stack", id: "terminal.sessions", label: String(localized: "Sessions")) { actions.perform(.sessions) }
                icon("rectangle.on.rectangle", id: "terminal.windows", label: String(localized: "Windows")) { actions.perform(.windows) }
                icon("square.split.2x1", id: "terminal.panes", label: String(localized: "Panes")) { actions.perform(.panes) }
            }
            controlGroup {
                icon(
                    "keyboard",
                    id: "terminal.keyboard",
                    label: keyboardMode == .hidden ? String(localized: "Show keyboard") : String(localized: "Hide keyboard"),
                    active: keyboardMode == .system
                ) { actions.perform(.keyboard) }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .onChange(of: presentedSheet) { _, sheet in
            onImagePresentationChange(sheet == .image)
        }
        .onDisappear { onImagePresentationChange(false) }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .keypad:
                GhosttyKeypadSheet(
                    isControlArmed: isControlArmed,
                    isAltArmed: isAltArmed,
                    onAddImage: imageUploader == nil ? nil : { presentedSheet = .image },
                    actions: actions
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            case .image:
                if let imageUploader {
                    GhosttyImageAttachmentSheet(
                        uploader: imageUploader,
                        insertPath: insertImagePath
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
        }
    }

    private func controlGroup<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 2, content: content)
            .padding(GhosttyKeyboardChromeSizing.controlGroupVerticalPadding)
            .background(.thinMaterial, in: Capsule())
    }

    private func key(_ title: String, id: String, active: Bool = false, action: @escaping () -> Bool) -> some View {
        Button { _ = action() } label: { Text(title).font(.system(size: 12, weight: .semibold)) }
            .buttonStyle(ChromeButtonStyle(active: active, accent: chromeStyle.accent))
            .accessibilityIdentifier(id)
            .disabled(!isEnabled)
    }

    private func icon(_ name: String, id: String, label: String, active: Bool = false, action: @escaping () -> Bool) -> some View {
        Button { _ = action() } label: { Image(systemName: name).font(.system(size: 16, weight: .semibold)) }
            .buttonStyle(ChromeButtonStyle(active: active, accent: chromeStyle.accent))
            .accessibilityLabel(label)
            .accessibilityIdentifier(id)
            .disabled(!isEnabled)
    }
}

private struct ChromeButtonStyle: ButtonStyle {
    let active: Bool
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: GhosttyKeyboardChromeSizing.dockButtonWidth, height: GhosttyKeyboardChromeSizing.dockButtonHeight)
            .foregroundStyle(active ? accent : Color.primary)
            .background(active ? accent.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: GhosttyKeyboardChromeSizing.dockButtonCornerRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

extension View {
    func ghosttyTerminalChromePresentation(_ colorScheme: ColorScheme, chromeStyle: GhosttyTerminalChromeStyle) -> some View {
        preferredColorScheme(colorScheme).environment(\.ghosttyTerminalChromeStyle, chromeStyle)
    }
}
