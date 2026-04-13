import SwiftUI

/// MoriRemote UI tokens aligned with the Mac app's quieter, denser workspace language.
enum Theme {
    // MARK: - Colors

    static let bg = Color(red: 0.07, green: 0.08, blue: 0.10)
    static let sidebarBg = Color(red: 0.08, green: 0.09, blue: 0.11)
    static let terminalBg = Color.black
    static let cardBg = Color.white.opacity(0.045)
    static let elevatedBg = Color.white.opacity(0.07)
    static let mutedSurface = Color.white.opacity(0.04)
    static let rowHover = Color.white.opacity(0.035)
    static let cardBorder = Color.white.opacity(0.08)
    static let divider = Color.white.opacity(0.08)

    static let accent = Color.accentColor
    static let accentSoft = Theme.accent.opacity(0.12)
    static let accentBorder = Theme.accent.opacity(0.28)

    static let success = Color.green.opacity(0.95)
    static let warning = Color.yellow.opacity(0.95)
    static let destructive = Color.red.opacity(0.9)

    static let textPrimary = Color.white.opacity(0.96)
    static let textSecondary = Color.white.opacity(0.64)
    static let textTertiary = Color.white.opacity(0.38)

    // MARK: - Spacing

    static let rowSpacing: CGFloat = 8
    static let sectionSpacing: CGFloat = 10
    static let contentInset: CGFloat = 16

    // MARK: - Shapes

    static let cardRadius: CGFloat = 10
    static let rowRadius: CGFloat = 7
    static let buttonRadius: CGFloat = 10
    static let sheetRadius: CGFloat = 20

    // MARK: - Typography

    static let sectionHeaderFont = Font.system(size: 11, weight: .bold)
    static let rowTitleFont = Font.system(size: 13.5, weight: .semibold)
    static let rowSubtitleFont = Font.system(size: 11)
    static let monoCaptionFont = Font.system(size: 10.5, design: .monospaced)
    static let monoDetailFont = Font.system(size: 11, design: .monospaced)
    static let shortcutFont = Font.system(size: 10, design: .monospaced)

    // MARK: - View Modifiers

    struct PanelStyle: ViewModifier {
        var padding: CGFloat = 16

        func body(content: Content) -> some View {
            content
                .padding(padding)
                .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius)
                        .strokeBorder(Theme.cardBorder, lineWidth: 1)
                )
        }
    }

    struct RowSurfaceStyle: ViewModifier {
        let isSelected: Bool

        func body(content: Content) -> some View {
            content
                .background(
                    isSelected ? Theme.accentSoft : Theme.mutedSurface,
                    in: RoundedRectangle(cornerRadius: Theme.rowRadius)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.rowRadius)
                        .strokeBorder(isSelected ? Theme.accentBorder : Theme.cardBorder, lineWidth: 1)
                )
        }
    }

    struct PrimaryButtonStyle: ButtonStyle {
        let disabled: Bool

        init(disabled: Bool = false) {
            self.disabled = disabled
        }

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(disabled ? Theme.textTertiary : Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    disabled ? Theme.accent.opacity(0.24) : Theme.accent,
                    in: RoundedRectangle(cornerRadius: Theme.buttonRadius)
                )
                .opacity(configuration.isPressed ? 0.92 : 1)
                .scaleEffect(configuration.isPressed ? 0.985 : 1)
                .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
        }
    }

    struct SecondaryButtonStyle: ButtonStyle {
        let foreground: Color
        let background: Color
        let border: Color

        init(
            foreground: Color = Theme.textPrimary,
            background: Color = Theme.mutedSurface,
            border: Color = Theme.cardBorder
        ) {
            self.foreground = foreground
            self.background = background
            self.border = border
        }

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(background, in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.buttonRadius)
                        .strokeBorder(border, lineWidth: 1)
                )
                .opacity(configuration.isPressed ? 0.88 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }

    struct DarkFieldStyle: ViewModifier {
        func body(content: Content) -> some View {
            content
                .font(.system(size: 14))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Theme.mutedSurface, in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.buttonRadius)
                        .strokeBorder(Theme.cardBorder, lineWidth: 1)
                )
                .foregroundStyle(Theme.textPrimary)
            }
    }
}

extension View {
    func cardStyle(padding: CGFloat = 16) -> some View {
        modifier(Theme.PanelStyle(padding: padding))
    }

    func rowSurfaceStyle(selected: Bool = false) -> some View {
        modifier(Theme.RowSurfaceStyle(isSelected: selected))
    }

    func darkFieldStyle() -> some View {
        modifier(Theme.DarkFieldStyle())
    }

    func moriSectionHeaderStyle() -> some View {
        self
            .font(Theme.sectionHeaderFont)
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(Theme.textTertiary)
    }
}
