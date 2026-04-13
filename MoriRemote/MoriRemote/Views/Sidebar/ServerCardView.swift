#if os(iOS)
import SwiftUI

/// Server summary block at the top of the tmux sidebar.
struct ServerCardView: View {
    let server: Server?
    let showsDismissButton: Bool
    let onSwitchHost: () -> Void
    let onDisconnect: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            actionButtons
        }
        .cardStyle(padding: 16)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .fill(server != nil ? Theme.accentSoft : Theme.mutedSurface)
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: "server.rack")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(server != nil ? Theme.accent : Theme.textSecondary)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Servers"))
                    .moriSectionHeaderStyle()

                Text(server?.displayName ?? String(localized: "Not Connected"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                Text(server?.subtitle ?? "—")
                    .font(Theme.monoCaptionFont)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if showsDismissButton {
                HStack(spacing: 8) {
                    connectionBadge

                    Button(action: onDismiss) {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(Theme.mutedSurface, in: RoundedRectangle(cornerRadius: 7))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(Theme.cardBorder, lineWidth: 1)
                            )
                    }
                }
            } else {
                connectionBadge
            }
        }
    }

    private var connectionBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(server != nil ? Theme.success : Theme.destructive)
                .frame(width: 6, height: 6)

            Text(server != nil ? String(localized: "Connected") : String(localized: "Offline"))
                .font(Theme.shortcutFont)
                .foregroundStyle(server != nil ? Theme.success : Theme.destructive)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.mutedSurface, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.cardBorder, lineWidth: 1)
        )
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button(action: onSwitchHost) {
                Label(String(localized: "Switch Host"), systemImage: "arrow.left.arrow.right")
            }
            .buttonStyle(Theme.SecondaryButtonStyle(
                foreground: Theme.textSecondary,
                background: Theme.mutedSurface,
                border: Theme.cardBorder
            ))

            Button(action: onDisconnect) {
                Label(String(localized: "Disconnect"), systemImage: "power")
            }
            .buttonStyle(Theme.SecondaryButtonStyle(
                foreground: Theme.destructive,
                background: Theme.destructive.opacity(0.10),
                border: Theme.destructive.opacity(0.24)
            ))
        }
    }
}
#endif
