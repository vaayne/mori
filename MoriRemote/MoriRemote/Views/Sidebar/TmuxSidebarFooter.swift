#if os(iOS)
import SwiftUI

/// Bottom bar of the tmux sidebar with "+ Window" and "+ Session" buttons.
struct TmuxSidebarFooter: View {
    let onNewWindow: () -> Void
    let onNewSession: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            footerButton(icon: "plus", label: "Window", action: onNewWindow)
            footerButton(icon: "plus", label: "Session", action: onNewSession)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.04))
                .frame(height: 1)
        }
    }

    private func footerButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Color.white.opacity(0.35))
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white.opacity(0.04), lineWidth: 1)
            )
        }
    }
}
#endif
