#if os(iOS)
import SwiftUI

/// Compact tmux window row aligned with the Mac sidebar row language.
struct TmuxWindowRow: View {
    let window: TmuxWindow
    let isActiveSession: Bool
    let onSelect: () -> Void
    let onNewAfter: () -> Void
    let onClose: () -> Void

    private var isHighlighted: Bool {
        window.isActive && isActiveSession
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Text("\(window.index)")
                    .font(Theme.shortcutFont)
                    .foregroundStyle(isHighlighted ? Theme.accent : Theme.textTertiary)
                    .frame(width: 20, alignment: .center)

                Image(systemName: window.isActive ? "rectangle.inset.filled" : "rectangle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isHighlighted ? Theme.accent : Theme.textSecondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(window.name)
                        .font(isHighlighted ? Theme.rowTitleFont : .system(size: 13.5, weight: .medium))
                        .foregroundStyle(isHighlighted ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)

                    if !window.shortPath.isEmpty {
                        Text(window.shortPath)
                            .font(Theme.monoCaptionFont)
                            .foregroundStyle(isHighlighted ? Theme.textSecondary : Theme.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if isHighlighted {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .rowSurfaceStyle(selected: isHighlighted)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onSelect()
            } label: {
                Label(String(localized: "Switch to Window"), systemImage: "arrow.up.right.square")
            }

            Divider()

            Button {
                onNewAfter()
            } label: {
                Label(String(localized: "New Window After"), systemImage: "plus.rectangle")
            }

            Divider()

            Button(role: .destructive) {
                onClose()
            } label: {
                Label(String(localized: "Close Window"), systemImage: "xmark.circle")
            }
        }
    }
}
#endif
