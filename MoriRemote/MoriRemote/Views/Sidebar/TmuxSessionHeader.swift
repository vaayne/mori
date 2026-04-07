#if os(iOS)
import SwiftUI

/// Flat uppercase session label with compact attached badge and context menu actions.
struct TmuxSessionHeader: View {
    let session: TmuxSession
    let isActive: Bool
    let onSwitch: () -> Void
    let onRename: () -> Void
    let onKill: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isActive ? Theme.accent : Theme.textTertiary)
                .frame(width: 6, height: 6)

            Text(session.name)
                .moriSectionHeaderStyle()
                .foregroundStyle(isActive ? Theme.textSecondary : Theme.textTertiary)

            Spacer(minLength: 8)

            if session.isAttached {
                Text(String(localized: "Connected"))
                    .font(Theme.shortcutFont)
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                onSwitch()
            } label: {
                Label(String(localized: "Switch to Session"), systemImage: "arrow.right.square")
            }

            Divider()

            Button {
                onRename()
            } label: {
                Label(String(localized: "Rename Session"), systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                onKill()
            } label: {
                Label(String(localized: "Kill Session"), systemImage: "xmark.circle")
            }
        }
    }
}
#endif
