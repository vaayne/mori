#if os(iOS)
import SwiftUI

/// Single tmux window row with left accent bar, index, icon, name, and active dot.
///
/// Active window shows a 3px teal left bar and highlighted background.
/// Long-press shows a context menu with Switch / New Window After / Close.
struct TmuxWindowRow: View {
    let window: TmuxWindow
    let isActiveSession: Bool
    let onSelect: () -> Void
    let onNewAfter: () -> Void
    let onClose: () -> Void

    /// Only highlight if this window is active AND belongs to the attached session.
    private var isHighlighted: Bool {
        window.isActive && isActiveSession
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                // Window index
                Text("\(window.index)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(
                        isHighlighted
                            ? Theme.accent.opacity(0.5)
                            : Color.white.opacity(0.2)
                    )
                    .frame(width: 16, alignment: .center)

                // Window icon
                Image(systemName: isHighlighted ? "square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundStyle(
                        isHighlighted ? Theme.accent : Color.white.opacity(0.25)
                    )

                // Window name + path
                VStack(alignment: .leading, spacing: 1) {
                    Text(window.name)
                        .font(.system(size: 14, weight: isHighlighted ? .semibold : .medium))
                        .foregroundStyle(
                            isHighlighted ? Theme.textPrimary : Color.white.opacity(0.55)
                        )
                        .lineLimit(1)

                    if !window.shortPath.isEmpty {
                        Text(window.shortPath)
                            .font(.system(size: 10))
                            .foregroundStyle(
                                isHighlighted
                                    ? Theme.accent.opacity(0.5)
                                    : Color.white.opacity(0.2)
                            )
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Active dot
                if isHighlighted {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(
                isHighlighted
                    ? Theme.accent.opacity(0.08)
                    : Color.clear
            )
            // Left accent bar for active window
            .overlay(alignment: .leading) {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.accent)
                        .frame(width: 3)
                        .padding(.vertical, 8)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            Button {
                onSelect()
            } label: {
                Label("Switch to Window", systemImage: "arrow.up.right.square")
            }

            Divider()

            Button {
                onNewAfter()
            } label: {
                Label("New Window After", systemImage: "plus.rectangle")
            }

            Divider()

            Button(role: .destructive) {
                onClose()
            } label: {
                Label("Close Window", systemImage: "xmark.circle")
            }
        }
    }
}
#endif
