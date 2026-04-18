import SwiftUI
import MoriCore

/// Small 18×18 rounded-square letter tile used in sidebar project headers.
/// Uses a deterministic duotone pair per project id so scanning becomes a
/// colour-match rather than a text-read.
struct ProjectLetterTile: View {
    let project: Project

    var body: some View {
        let pair = MoriTokens.ProjectPalette.pair(for: project.id)
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(pair.background)
            Text(letter)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(pair.foreground)
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }

    private var letter: String {
        let trimmed = project.name.trimmingCharacters(in: .whitespaces)
        return String(trimmed.first.map(String.init) ?? "·").uppercased()
    }
}
