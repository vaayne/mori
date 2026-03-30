#if os(iOS)
import SwiftUI

/// Server info card at the top of the tmux sidebar.
///
/// Shows server avatar, name, user@host, connection status dot,
/// and action buttons for "Switch Host" and "Disconnect".
struct ServerCardView: View {
    let server: Server?
    let onSwitchHost: () -> Void
    let onDisconnect: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            topRow
            actionButtons
        }
        .padding(12)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
        )
        .padding(.horizontal, 10)
        .padding(.top, 12)
    }

    // MARK: - Top Row

    private var topRow: some View {
        HStack(spacing: 10) {
            // Avatar
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.accent.opacity(0.1))
                .frame(width: 36, height: 36)
                .overlay {
                    Text("🖥")
                        .font(.system(size: 16))
                }

            // Server info
            VStack(alignment: .leading, spacing: 2) {
                Text(server?.displayName ?? "Not Connected")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Circle()
                        .fill(server != nil ? Theme.accent : Theme.destructive)
                        .frame(width: 6, height: 6)

                    Text(server?.subtitle ?? "—")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Close button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 6) {
            Button(action: onSwitchHost) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 10))
                    Text("Switch Host")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Color.white.opacity(0.5))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
            }

            Button(action: onDisconnect) {
                HStack(spacing: 5) {
                    Image(systemName: "power")
                        .font(.system(size: 10))
                    Text("Disconnect")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Theme.destructive)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(Theme.destructive.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Theme.destructive.opacity(0.15), lineWidth: 1)
                )
            }
        }
    }
}
#endif
