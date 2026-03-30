#if os(iOS)
import SwiftUI

/// Slide-over sidebar showing tmux sessions and windows.
///
/// Sessions are shown as expandable groups; windows as tappable rows.
/// Active window is highlighted with the accent color.
struct TmuxSidebarView: View {
    @Environment(ShellCoordinator.self) private var coordinator

    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.06))
            sessionList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "rectangle.grid.1x2")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)

            Text("Sessions")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            Spacer()

            Menu {
                Button {
                    coordinator.newTmuxWindow()
                } label: {
                    Label("New Window", systemImage: "plus.rectangle")
                }

                Button {
                    coordinator.newTmuxSession()
                } label: {
                    Label("New Session", systemImage: "plus.square.on.square")
                }

                Divider()

                Button {
                    coordinator.refreshTmuxState()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Session List

    private var sessionList: some View {
        ScrollView {
            if coordinator.tmuxSessions.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 2) {
                    ForEach(coordinator.tmuxSessions) { session in
                        TmuxSessionGroup(
                            session: session,
                            isActiveSession: session.name == coordinator.tmuxActiveSession?.name,
                            onSelectWindow: { window in
                                coordinator.selectTmuxWindow(
                                    session: session.name,
                                    windowIndex: window.index
                                )
                                onDismiss()
                            },
                            onCloseWindow: { window in
                                coordinator.closeTmuxWindow(
                                    session: session.name,
                                    windowIndex: window.index
                                )
                            },
                            onSwitchSession: {
                                coordinator.switchTmuxSession(session.name)
                                onDismiss()
                            },
                            onCloseSession: {
                                coordinator.closeTmuxSession(session.name)
                            }
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 28))
                .foregroundStyle(Theme.textTertiary)

            Text("No tmux sessions")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)

            Text("Start tmux in your terminal to see sessions here.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
        .padding(.horizontal, 20)
    }
}

// MARK: - Session Group

private struct TmuxSessionGroup: View {
    let session: TmuxSession
    let isActiveSession: Bool
    let onSelectWindow: (TmuxWindow) -> Void
    let onCloseWindow: (TmuxWindow) -> Void
    let onSwitchSession: () -> Void
    let onCloseSession: () -> Void

    @State private var isExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            // Session header
            sessionHeader

            // Windows
            if isExpanded {
                ForEach(session.windows) { window in
                    windowRow(window)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(isActiveSession ? 0.04 : 0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isActiveSession ? Theme.accent.opacity(0.15) : Color.clear,
                    lineWidth: 1
                )
        )
        .padding(.vertical, 2)
    }

    private var sessionHeader: some View {
        Button {
            if isActiveSession {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } else {
                onSwitchSession()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 16)

                Circle()
                    .fill(isActiveSession ? Theme.accent : Theme.textTertiary)
                    .frame(width: 6, height: 6)

                Text(session.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isActiveSession ? Theme.accent : Theme.textSecondary)

                Text("\(session.windowCount)w")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)

                if session.isAttached {
                    Text("attached")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.accent.opacity(0.7))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.accent.opacity(0.1), in: Capsule())
                }

                Spacer()

                Menu {
                    Button {
                        onSwitchSession()
                    } label: {
                        Label("Switch to Session", systemImage: "arrow.right.square")
                    }

                    Divider()

                    Button(role: .destructive) {
                        onCloseSession()
                    } label: {
                        Label("Kill Session", systemImage: "xmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 24, height: 24)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func windowRow(_ window: TmuxWindow) -> some View {
        Button {
            onSelectWindow(window)
        } label: {
            HStack(spacing: 8) {
                Color.clear.frame(width: 16) // indent

                Image(systemName: window.isActive ? "terminal.fill" : "terminal")
                    .font(.system(size: 11))
                    .foregroundStyle(
                        window.isActive ? Theme.accent : Theme.textTertiary
                    )

                Text("\(window.index)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)

                Text(window.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(
                        window.isActive ? Theme.textPrimary : Theme.textSecondary
                    )
                    .lineLimit(1)

                Spacer()

                if window.isActive {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                window.isActive
                    ? Theme.accent.opacity(0.08)
                    : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onCloseWindow(window)
            } label: {
                Label("Close", systemImage: "xmark")
            }
        }
    }
}
#endif
