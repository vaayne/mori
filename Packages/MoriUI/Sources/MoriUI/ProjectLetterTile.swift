import SwiftUI
import MoriCore

/// Small rounded-square letter tile used in sidebar project headers.
/// Uses a deterministic duotone pair per project id so scanning becomes a
/// colour-match rather than a text-read.
struct ProjectLetterTile: View {
    let project: Project
    var size: CGFloat = MoriTokens.Size.projectTile
    var cornerRadius: CGFloat = MoriTokens.Radius.projectTile
    var fontSize: CGFloat = 10

    var body: some View {
        let pair = MoriTokens.ProjectPalette.pair(for: project.id)
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(pair.background)
            Text(letter)
                .font(.system(size: fontSize, weight: .semibold, design: .monospaced))
                .foregroundStyle(pair.foreground)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var letter: String {
        let trimmed = project.name.trimmingCharacters(in: .whitespaces)
        return String(trimmed.first.map(String.init) ?? "·").uppercased()
    }
}
