import SwiftUI

enum GhosttyKeyboardChromeMode: Equatable {
    case hidden
    case system

    var enablesSystemKeyboard: Bool {
        self == .system
    }

    func toggledKeyboard() -> Self {
        self == .hidden ? .system : .hidden
    }

    func applyingSystemKeyboardVisibility(_ isVisible: Bool) -> Self {
        isVisible ? .system : .hidden
    }
}

enum GhosttyKeyboardChromeSizing {
    static let dockButtonHeight: CGFloat = 38
    static let dockButtonWidth: CGFloat = 38
    static let compactDockButtonWidth: CGFloat = 35
    static let controlGroupVerticalPadding: CGFloat = 4
    static let baselineHeight = dockButtonHeight + (controlGroupVerticalPadding * 2)

    static func keyboardReplacementHeight(
        keyboardOverlapHeight: CGFloat,
        bottomSafeAreaHeight: CGFloat
    ) -> CGFloat {
        guard keyboardOverlapHeight.isFinite, keyboardOverlapHeight > 0 else {
            return 0
        }
        return ceil(max(0, keyboardOverlapHeight - max(0, bottomSafeAreaHeight)))
    }
}

struct GhosttyBottomChromeReservation: Equatable {
    private(set) var settledHeight: CGFloat = 0

    func layoutHeight(fallback: CGFloat) -> CGFloat {
        settledHeight > 0 ? settledHeight : fallback
    }

    @discardableResult
    mutating func observe(renderedHeight: CGFloat, isTransient: Bool) -> Bool {
        guard !isTransient, renderedHeight.isFinite, renderedHeight > 0 else {
            return false
        }
        let normalizedHeight = ceil(renderedHeight)
        guard settledHeight != normalizedHeight else {
            return false
        }
        settledHeight = normalizedHeight
        return true
    }
}

struct GhosttyPhoneChromeLayout: Equatable {
    let screenSize: CGSize

    var isLandscape: Bool {
        screenSize.width > screenSize.height
    }

    var isCompact: Bool {
        isLandscape || screenSize.width < 420
    }

    var surfaceHorizontalPadding: CGFloat {
        isCompact ? 8 : 12
    }

    var bottomPadding: CGFloat {
        isCompact ? 2 : 4
    }
}

struct GhosttyRenderedBottomChromeHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct GhosttyTerminalChromeStyle {
    let accent: Color
    let accentForeground: Color

    var toolbarButtonActiveFill: Color {
        accent.opacity(0.16)
    }

    static let ghosttyDefault = Self(
        accent: Color(uiColor: .ghosttyDefaultTerminalChromeAccent),
        accentForeground: Color(uiColor: .terminalChromeAccentForegroundForDarkAccent)
    )
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

/// Testable action boundary for the terminal's persistent controls.
struct GhosttyKeyboardChromeActions {
    let showSessions: () -> Void
    let showAgents: () -> Void
    let showLibrary: () -> Void
    let toggleKeyboard: () -> Void
    let toggleControl: () -> Void
    let toggleAlt: () -> Void
    let requestSharedMutation: (MoriRemoteTerminalSharedMutation) -> Void
    let sendShortcut: (String) -> Bool
    let sendKey: (GhosttySurfaceKeyEvent) -> Bool

    func perform(_ action: Action) -> Bool {
        switch action {
        case .sessions:
            showSessions()
            return true
        case .agents:
            showAgents()
            return true
        case .library:
            showLibrary()
            return true
        case .keyboard:
            toggleKeyboard()
            return true
        case .control:
            toggleControl()
            return true
        case .alt:
            toggleAlt()
            return true
        case .newWindow:
            requestSharedMutation(.newWindow)
            return true
        case .splitHorizontal:
            requestSharedMutation(.splitHorizontal)
            return true
        case .splitVertical:
            requestSharedMutation(.splitVertical)
            return true
        case .closePane:
            requestSharedMutation(.closePane)
            return true
        case .closeWindow:
            requestSharedMutation(.closeWindow)
            return true
        case .ctrlC:
            return sendShortcut("\u{03}")
        case .ctrlD:
            return sendShortcut("\u{04}")
        case .ctrlZ:
            return sendShortcut("\u{1A}")
        case .ctrlL:
            return sendShortcut("\u{0C}")
        case .ctrlA:
            return sendShortcut("\u{01}")
        case .ctrlE:
            return sendShortcut("\u{05}")
        case .ctrlR:
            return sendShortcut("\u{12}")
        case .ctrlU:
            return sendShortcut("\u{15}")
        case .ctrlK:
            return sendShortcut("\u{0B}")
        case .ctrlW:
            return sendShortcut("\u{17}")
        case .altB:
            return sendShortcut("\u{1B}b")
        case .altF:
            return sendShortcut("\u{1B}f")
        case .escape:
            return sendKey(.init(keyCode: .escape))
        case .tab:
            return sendKey(.init(keyCode: .tab))
        case .shiftTab:
            return sendKey(.init(keyCode: .tab, mods: .shift))
        case .arrowLeft:
            return sendKey(.init(keyCode: .arrowLeft))
        case .arrowUp:
            return sendKey(.init(keyCode: .arrowUp))
        case .arrowDown:
            return sendKey(.init(keyCode: .arrowDown))
        case .arrowRight:
            return sendKey(.init(keyCode: .arrowRight))
        case .home:
            return sendKey(.init(keyCode: .home))
        case .end:
            return sendKey(.init(keyCode: .end))
        case .pageUp:
            return sendKey(.init(keyCode: .pageUp))
        case .pageDown:
            return sendKey(.init(keyCode: .pageDown))
        case .questionMark:
            return sendKey(.init(
                keyCode: .slash,
                text: "?",
                mods: .shift,
                consumedMods: .shift,
                unshiftedCodepoint: 0x2F
            ))
        case .slash:
            return sendKey(.init(
                keyCode: .slash,
                text: "/",
                unshiftedCodepoint: 0x2F
            ))
        }
    }

    enum Action {
        case sessions, agents, library, keyboard, control, alt
        case escape, tab, shiftTab, arrowLeft, arrowUp, arrowDown, arrowRight
        case home, end, pageUp, pageDown, questionMark, slash
        case ctrlC, ctrlD, ctrlZ, ctrlL, ctrlA, ctrlE, ctrlR, ctrlU, ctrlK, ctrlW, altB, altF
        case newWindow, splitHorizontal, splitVertical, closePane, closeWindow
    }
}

struct GhosttyKeyboardChrome: View {
    private enum PresentedSheet: String, Identifiable {
        case keypad
        case image

        var id: Self {
            self
        }
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
        chromeContainer
            .fixedSize(horizontal: false, vertical: true)
            .onAppear {
                Haptic.prewarmChromeFeedback()
            }
            .onChange(of: presentedSheet) { _, sheet in
                onImagePresentationChange(sheet == .image)
            }
            .onDisappear {
                onImagePresentationChange(false)
            }
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

    @ViewBuilder
    private var chromeContainer: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: isCompact ? 6 : 10) {
                selectorRow
            }
        } else {
            selectorRow
        }
    }

    private var selectorRow: some View {
        HStack(spacing: isCompact ? 6 : 10) {
            keyGroup
            navigationGroup
            inputGroup
        }
        .frame(maxWidth: .infinity)
    }

    private var keyGroup: some View {
        group {
            HStack(spacing: isCompact ? 1 : 2) {
                key("ctrl", id: "terminal.ctrl", active: isControlArmed) {
                    actions.perform(.control)
                }
                key("esc", id: "terminal.esc") {
                    actions.perform(.escape)
                }
                key("tab", id: "terminal.tab") {
                    actions.perform(.tab)
                }
            }
        }
    }

    private var navigationGroup: some View {
        group {
            HStack(spacing: isCompact ? 1 : 2) {
                dock(
                    "rectangle.stack",
                    id: "terminal.sessions",
                    label: String(localized: "Sessions"),
                    enabled: true
                ) {
                    _ = actions.perform(.sessions)
                }
                dock(
                    "person.2",
                    id: "terminal.agents",
                    label: String(localized: "Agents"),
                    enabled: true
                ) {
                    _ = actions.perform(.agents)
                }
            }
        }
    }

    private var inputGroup: some View {
        group {
            HStack(spacing: isCompact ? 1 : 2) {
                dock(
                    "house",
                    id: "terminal.home",
                    label: String(localized: "Home"),
                    enabled: true
                ) {
                    _ = actions.perform(.library)
                }
                dock(
                    "square.and.pencil",
                    id: "terminal.composer.toggle",
                    label: String(localized: "Open keypad"),
                    enabled: isEnabled
                ) {
                    presentedSheet = .keypad
                }
                dock(
                    "keyboard",
                    id: "terminal.keyboard",
                    label: keyboardMode == .hidden
                        ? String(localized: "Show keyboard")
                        : String(localized: "Hide keyboard"),
                    active: keyboardMode == .system,
                    enabled: isEnabled
                ) {
                    _ = actions.perform(.keyboard)
                }
            }
        }
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, isCompact ? 3 : 5)
            .padding(.vertical, GhosttyKeyboardChromeSizing.controlGroupVerticalPadding)
            .ghosttyToolbarGroupSurface()
    }

    private func key(
        _ title: String,
        id: String,
        active: Bool = false,
        action: @escaping () -> Bool
    ) -> some View {
        GhosttyKeyboardKeyButton(
            title: title,
            accessibilityIdentifier: id,
            chromeStyle: chromeStyle,
            width: dockWidth,
            height: GhosttyKeyboardChromeSizing.dockButtonHeight,
            isActive: active,
            isEnabled: isEnabled,
            action: action
        )
    }

    private func dock(
        _ symbol: String,
        id: String,
        label: String,
        badge: String? = nil,
        active: Bool = false,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        GhosttyKeyboardChromeDockButton(
            systemName: symbol,
            badge: badge,
            chromeStyle: chromeStyle,
            width: dockWidth,
            height: GhosttyKeyboardChromeSizing.dockButtonHeight,
            accessibilityLabel: label,
            accessibilityIdentifier: id,
            isActive: active,
            isEnabled: enabled,
            action: action
        )
    }

    private var dockWidth: CGFloat {
        isCompact
            ? GhosttyKeyboardChromeSizing.compactDockButtonWidth
            : GhosttyKeyboardChromeSizing.dockButtonWidth
    }

}

private struct GhosttyKeyboardChromeDockButton: View {
    let systemName: String
    let badge: String?
    let chromeStyle: GhosttyTerminalChromeStyle
    let width: CGFloat
    let height: CGFloat
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let isActive: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: systemName)
                    .font(.system(size: 16.5, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .contentTransition(.symbolEffect(.replace))

                if let badge {
                    dockBadge(badge)
                }
            }
        }
        .buttonStyle(GhosttyChromeDockButtonStyle(
            isActive: isActive,
            isEnabled: isEnabled,
            chromeStyle: chromeStyle,
            width: width,
            height: height
        ))
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func dockBadge(_ value: String) -> some View {
        let horizontalPadding: CGFloat = value.count > 1 ? 3 : 0

        return Text(value)
            .font(.system(size: 8, weight: .semibold).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(chromeStyle.accentForeground)
            .frame(minWidth: 12.5, minHeight: 12.5)
            .padding(.horizontal, horizontalPadding)
            .background(chromeStyle.accent.opacity(0.88), in: Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.top, 4)
            .padding(.trailing, 4)
    }
}

private struct GhosttyKeyboardKeyButton: View {
    let title: String
    let accessibilityIdentifier: String
    let chromeStyle: GhosttyTerminalChromeStyle
    let width: CGFloat
    let height: CGFloat
    let isActive: Bool
    let isEnabled: Bool
    let action: () -> Bool

    var body: some View {
        Button {
            if isEnabled {
                _ = action()
            }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .buttonStyle(GhosttyChromeKeyButtonStyle(
            isActive: isActive,
            isEnabled: isEnabled,
            chromeStyle: chromeStyle,
            width: width,
            height: height
        ))
        .disabled(!isEnabled)
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

/// Shared press primitive for dock buttons. Owns the press scale,
/// disabled opacity, and rising-edge feedback dispatch.
private struct GhosttyChromePressBody<Content: View>: View {
    let isPressed: Bool
    let isEnabled: Bool
    let onPressDown: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var lastPressed = false

    var body: some View {
        content()
            .scaleEffect(isPressed && isEnabled ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.42)
            .onChange(of: isPressed) { _, nowPressed in
                let wasPressed = lastPressed
                lastPressed = nowPressed
                guard isEnabled, nowPressed, !wasPressed else { return }
                onPressDown()
            }
    }
}

private struct GhosttyChromeDockButtonStyle: ButtonStyle {
    let isActive: Bool
    let isEnabled: Bool
    let chromeStyle: GhosttyTerminalChromeStyle
    let width: CGFloat
    let height: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        GhosttyChromePressBody(
            isPressed: configuration.isPressed,
            isEnabled: isEnabled,
            onPressDown: { Haptic.chromeControlPress() }
        ) {
            configuration.label
                .foregroundStyle(isActive ? chromeStyle.accent : GhosttyPhoneChromePalette.chromeForeground)
                .frame(width: width, height: height)
                .ghosttyToolbarButtonSurface(
                    isActive: isActive,
                    isPressed: configuration.isPressed,
                    isEnabled: isEnabled,
                    chromeStyle: chromeStyle
                )
                .contentShape(Rectangle())
        }
    }
}

private struct GhosttyChromeKeyButtonStyle: ButtonStyle {
    let isActive: Bool
    let isEnabled: Bool
    let chromeStyle: GhosttyTerminalChromeStyle
    let width: CGFloat
    let height: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        GhosttyChromePressBody(
            isPressed: configuration.isPressed,
            isEnabled: isEnabled,
            onPressDown: { Haptic.keyboardPress() }
        ) {
            configuration.label
                .foregroundStyle(
                    isActive ? chromeStyle.accent : GhosttyPhoneChromePalette.chromeForeground
                )
                .frame(width: width, height: height)
                .ghosttyToolbarButtonSurface(
                    isActive: isActive,
                    isPressed: configuration.isPressed,
                    isEnabled: isEnabled,
                    chromeStyle: chromeStyle
                )
                .contentShape(Rectangle())
        }
    }
}

private extension View {
    @ViewBuilder
    func ghosttyToolbarGroupSurface() -> some View {
        ghosttyToolbarSurface(in: Capsule())
    }

    @ViewBuilder
    private func ghosttyToolbarSurface<S: InsettableShape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect(
                    .regular
                        .tint(GhosttyPhoneChromePalette.toolbarGlassTint)
                        .interactive(),
                    in: shape
                )
                .overlay {
                    shape.strokeBorder(GhosttyPhoneChromePalette.toolbarGlassStroke, lineWidth: 0.75)
                }
                .shadow(color: GhosttyPhoneChromePalette.toolbarGlassShadow, radius: 13, y: 7)
        } else {
            self
                .background(GhosttyPhoneChromePalette.toolbarFallbackFill, in: shape)
                .overlay {
                    shape.strokeBorder(GhosttyPhoneChromePalette.toolbarStroke, lineWidth: 1)
                }
                .shadow(color: GhosttyPhoneChromePalette.toolbarShadow, radius: 8, y: 4)
        }
    }

    @ViewBuilder
    func ghosttyToolbarButtonSurface(
        isActive: Bool,
        isPressed: Bool,
        isEnabled: Bool,
        chromeStyle: GhosttyTerminalChromeStyle
    ) -> some View {
        let shape = Circle()

        self
            .background(isActive ? chromeStyle.toolbarButtonActiveFill : Color.clear, in: shape)
            .overlay {
                shape.fill(isPressed && isEnabled ? GhosttyPhoneChromePalette.toolbarButtonPressedFill : Color.clear)
            }
    }
}

enum GhosttyPhoneChromePalette {
    static let dock = Color(red: 0.15, green: 0.16, blue: 0.20)
    static let chromeForeground = Color.primary.opacity(0.84)
    static let toolbarGlassTint = Color.primary.opacity(0.065)
    static let toolbarGlassStroke = Color.primary.opacity(0.16)
    static let toolbarGlassShadow = Color.black.opacity(0.16)
    static let toolbarFallbackFill = Color(uiColor: .secondarySystemBackground).opacity(0.88)
    static let toolbarStroke = Color.primary.opacity(0.12)
    static let toolbarShadow = Color.black.opacity(0.18)
    static let toolbarButtonPressedFill = Color.primary.opacity(0.08)
}
private extension UIColor {
    static let ghosttyDefaultTerminalChromeAccent = UIColor(
        red: 0.38,
        green: 0.69,
        blue: 0.94,
        alpha: 1
    )
    static let terminalChromeAccentForegroundForDarkAccent = UIColor.black
        .withAlphaComponent(0.74)
}

extension View {
    func ghosttyTerminalChromePresentation() -> some View {
        preferredColorScheme(.dark)
            .environment(\.ghosttyTerminalChromeStyle, .ghosttyDefault)
    }
}
