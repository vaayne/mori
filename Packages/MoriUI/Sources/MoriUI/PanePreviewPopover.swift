import SwiftUI

/// A popover view showing the last N lines of captured pane output.
/// Monospaced text on a dark background, designed for hover preview.
public struct PanePreviewPopover: View {
    let output: String
    let maxLines: Int

    public init(output: String, maxLines: Int = 8) {
        self.output = output
        self.maxLines = maxLines
    }

    public var body: some View {
        let lines = lastLines(from: output, count: maxLines)

        VStack(alignment: .leading, spacing: 0) {
            if lines.isEmpty {
                Text(String.localized("No output"))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(MoriTokens.Spacing.lg)
            } else {
                Text(lines.joined(separator: "\n"))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(nil)
                    .textSelection(.enabled)
                    .padding(MoriTokens.Spacing.lg)
            }
        }
        .frame(minWidth: 280, maxWidth: 420, alignment: .leading)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: MoriTokens.Radius.medium))
    }

    private func lastLines(from text: String, count: Int) -> [String] {
        let allLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // Trim trailing empty lines
        var trimmed = allLines
        while trimmed.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            trimmed.removeLast()
        }
        if trimmed.count <= count {
            return trimmed
        }
        return Array(trimmed.suffix(count))
    }
}
