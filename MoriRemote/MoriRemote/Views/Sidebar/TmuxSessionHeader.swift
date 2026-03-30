#if os(iOS)
import SwiftUI

/// Flat uppercase session label with attached badge and long-press context menu.
///
/// Matches the design mockup's non-expandable session header style.
struct TmuxSessionHeader: View {
    let session: TmuxSession
    let isActive: Bool
    let onSwitch: () -> Void
    let onRename: () -> Void
    let onKill: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "hexagon")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.2))

            Text(session.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.3))
                .textCase(.uppercase)
                .tracking(0.5)

            Spacer()

            if session.isAttached {
                Text("attached")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                onSwitch()
            } label: {
                Label("Switch to Session", systemImage: "arrow.right.square")
            }

            Divider()

            Button {
                onRename()
            } label: {
                Label("Rename Session", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                onKill()
            } label: {
                Label("Kill Session", systemImage: "xmark.circle")
            }
        }
    }
}
#endif
