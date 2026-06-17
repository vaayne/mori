#if os(iOS)
import SwiftUI

/// Compact pane sub-row shown under a tmux window, with optional agent badge.
struct TmuxPaneRow: View {
    let pane: TmuxPane
    let isHighlighted: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: pane.isActive ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isHighlighted ? Theme.accent : Theme.textTertiary)
                    .frame(width: 16)

                Text(pane.displayLabel)
                    .font(.system(size: 12, weight: isHighlighted ? .semibold : .regular))
                    .foregroundStyle(isHighlighted ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 6)

                if let state = pane.agentState, !state.isEmpty {
                    Text(state)
                        .font(Theme.shortcutFont)
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .rowSurfaceStyle(selected: isHighlighted)
        }
        .buttonStyle(.plain)
    }
}
#endif
