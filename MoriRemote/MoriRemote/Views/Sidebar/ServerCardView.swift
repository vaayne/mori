#if os(iOS)
import SwiftUI

/// Server info card at the top of the tmux sidebar.
///
/// Shows server avatar, name, user@host, connection status dot,
/// and action buttons for "Switch Host" and "Disconnect".
struct ServerCardView: View {
    let server: Server?
    let showsDismissButton: Bool
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

    private var topRow: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.accent.opacity(0.1))
                .frame(width: 36, height: 36)
                .overlay {
                    Text("🖥")
                        .font(.system(size: 16))
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(server?.displayName ?? String(localized: "Not Connected"))
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

            if showsDismissButton {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                }
            } else {
                connectionBadge
            }
        }
    }

    private var connectionBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(server != nil ? Theme.accent : Theme.destructive)
                .frame(width: 6, height: 6)

            Text(server != nil ? String(localized: "Connected") : String(localized: "Offline"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(server != nil ? Theme.accent : Theme.destructive)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.04), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private var actionButtons: some View {
        HStack(spacing: 6) {
            actionButton(
                title: String(localized: "Switch Host"),
                systemImage: "arrow.left.arrow.right",
                foregroundStyle: Color.white.opacity(0.5),
                backgroundColor: Color.white.opacity(0.05),
                borderColor: Color.white.opacity(0.06),
                action: onSwitchHost
            )

            actionButton(
                title: String(localized: "Disconnect"),
                systemImage: "power",
                foregroundStyle: Theme.destructive,
                backgroundColor: Theme.destructive.opacity(0.08),
                borderColor: Theme.destructive.opacity(0.15),
                action: onDisconnect
            )
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        foregroundStyle: some ShapeStyle,
        backgroundColor: Color,
        borderColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(foregroundStyle)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
        }
    }
}
#endif
