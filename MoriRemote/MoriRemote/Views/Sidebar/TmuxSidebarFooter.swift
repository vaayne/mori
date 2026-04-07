#if os(iOS)
import SwiftUI

/// Footer actions for tmux sidebar creation workflows.
struct TmuxSidebarFooter: View {
    let onNewWindow: () -> Void
    let onNewSession: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            footerButton(icon: "plus", label: String(localized: "Window"), action: onNewWindow)
            footerButton(icon: "plus", label: String(localized: "Session"), action: onNewSession)
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Theme.sidebarBg)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)
        }
    }

    private func footerButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(Theme.mutedSurface, in: RoundedRectangle(cornerRadius: Theme.rowRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.rowRadius)
                    .strokeBorder(Theme.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
#endif
