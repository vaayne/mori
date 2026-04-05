import SwiftUI

/// Capsule background for shortcut hint badges.
/// Uses `.regularMaterial` with a subtle white stroke and drop shadow.
struct ShortcutHintPillBackground: View {
    var emphasis: Double = 1.0

    var body: some View {
        Capsule(style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.30 * emphasis), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.22 * emphasis), radius: 2, x: 0, y: 1)
    }
}

/// A pill-shaped badge displaying a keyboard shortcut string (e.g. "⌘B", "⇧⌘P").
public struct ShortcutHintPill: View {
    let text: String
    var fontSize: CGFloat = 10

    public init(_ text: String, fontSize: CGFloat = 10) {
        self.text = text
        self.fontSize = fontSize
    }

    public var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundColor(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(ShortcutHintPillBackground())
    }
}
