import SwiftUI
import MoriCore

/// Small rounded-square letter tile used in sidebar project headers.
/// Uses a deterministic duotone pair per project id so scanning becomes a
/// colour-match rather than a text-read.
struct ProjectLetterTile: View {
    let project: Project

    var body: some View {
        let pair = MoriTokens.ProjectPalette.pair(for: project.id)
        ZStack {
            RoundedRectangle(cornerRadius: MoriTokens.Radius.projectTile)
                .fill(pair.background)
            Text(letter)
                .font(MoriTokens.Font.projectTile)
                .foregroundStyle(pair.foreground)
        }
        .frame(width: MoriTokens.Size.projectTile, height: MoriTokens.Size.projectTile)
        .accessibilityHidden(true)
    }

    private var letter: String {
        let trimmed = project.name.trimmingCharacters(in: .whitespaces)
        return String(trimmed.first.map(String.init) ?? "·").uppercased()
    }
}
