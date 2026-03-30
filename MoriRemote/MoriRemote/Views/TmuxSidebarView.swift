#if os(iOS)
import SwiftUI

/// Slide-over sidebar showing server info and tmux sessions/windows.
///
/// Layout matches the design mockup:
/// - Server card at top (name, status, Switch Host / Disconnect)
/// - Flat session labels (uppercase, always expanded) with windows
/// - Footer with + Window / + Session buttons
/// - Long-press context menus on sessions and windows
struct TmuxSidebarView: View {
    @Environment(ShellCoordinator.self) private var coordinator

    let onDismiss: () -> Void
    let onDisconnect: () -> Void
    var onSwitchHost: (() -> Void)?

    @State private var renameTarget: TmuxSession?
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 0) {
            ServerCardView(
                server: coordinator.activeServer,
                onSwitchHost: { onSwitchHost?() },
                onDisconnect: {
                    onDismiss()
                    onDisconnect()
                },
                onDismiss: onDismiss
            )

            divider

            if coordinator.tmuxSessions.isEmpty {
                emptyState
            } else {
                sessionList
            }

            if !coordinator.tmuxSessions.isEmpty {
                TmuxSidebarFooter(
                    onNewWindow: { coordinator.newTmuxWindow() },
                    onNewSession: { coordinator.newTmuxSession() }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.07, green: 0.07, blue: 0.10))
        .alert("Rename Session", isPresented: showRenameAlert) {
            TextField("Session name", text: $renameText)
            Button("Cancel", role: .cancel) { }
            Button("Rename") {
                if let session = renameTarget, !renameText.isEmpty {
                    coordinator.renameTmuxSession(session.name, to: renameText)
                }
            }
        }
    }

    // MARK: - Subviews

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.04))
            .frame(height: 1)
            .padding(.horizontal, 16)
            .padding(.top, 12)
    }

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(coordinator.tmuxSessions) { session in
                    let isActive = session.name == coordinator.tmuxActiveSession?.name

                    TmuxSessionHeader(
                        session: session,
                        isActive: isActive,
                        onSwitch: {
                            coordinator.switchTmuxSession(session.name)
                            onDismiss()
                        },
                        onRename: {
                            renameTarget = session
                            renameText = session.name
                        },
                        onKill: {
                            coordinator.closeTmuxSession(session.name)
                        }
                    )

                    let isActiveSession = session.name == coordinator.tmuxActiveSession?.name

                    ForEach(session.windows) { window in
                        TmuxWindowRow(
                            window: window,
                            isActiveSession: isActiveSession,
                            onSelect: {
                                coordinator.selectTmuxWindow(
                                    session: session.name,
                                    windowIndex: window.index
                                )
                                onDismiss()
                            },
                            onNewAfter: {
                                coordinator.newTmuxWindowAfter(
                                    session: session.name,
                                    windowIndex: window.index
                                )
                            },
                            onClose: {
                                coordinator.closeTmuxWindow(
                                    session: session.name,
                                    windowIndex: window.index
                                )
                            }
                        )
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()

            Image(systemName: "square.grid.2x2")
                .font(.system(size: 28))
                .foregroundStyle(Color.white.opacity(0.1))

            Text("No tmux sessions")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.25))

            Text("Start tmux to manage\nwindows from here.")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.15))
                .multilineTextAlignment(.center)

            Button {
                coordinator.newTmuxSession()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                    Text("New Session")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Theme.accent.opacity(0.15), lineWidth: 1)
                )
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Rename Alert Binding

    private var showRenameAlert: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }
}
#endif
