import SwiftUI

/// Design tokens for the app's dark terminal theme.
enum Theme {
    // MARK: - Colors

    static let bg = Color(red: 0.07, green: 0.07, blue: 0.09)
    static let cardBg = Color(red: 0.11, green: 0.11, blue: 0.14)
    static let cardBorder = Color.white.opacity(0.06)
    static let accent = Color(red: 0.30, green: 0.85, blue: 0.75) // teal / cyan
    static let destructive = Color(red: 0.95, green: 0.35, blue: 0.35)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.35)

    // MARK: - Shapes

    static let cardRadius: CGFloat = 14
    static let buttonRadius: CGFloat = 12
    static let sheetRadius: CGFloat = 24

    // MARK: - View Modifiers

    struct CardStyle: ViewModifier {
        func body(content: Content) -> some View {
            content
                .padding(16)
                .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius)
                        .strokeBorder(Theme.cardBorder, lineWidth: 1)
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
                .font(.body.weight(.semibold))
                .foregroundStyle(disabled ? Theme.textTertiary : Theme.bg)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    disabled ? Theme.accent.opacity(0.3) : Theme.accent,
                    in: RoundedRectangle(cornerRadius: Theme.buttonRadius)
                )
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
        }
    }

    struct DarkFieldStyle: ViewModifier {
        func body(content: Content) -> some View {
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(Theme.CardStyle())
    }

    func darkFieldStyle() -> some View {
        modifier(Theme.DarkFieldStyle())
    }
}
