#if os(iOS)
import SwiftUI

enum TmuxSidebarPresentation {
    case overlay
    case persistent

    var showsDismissButton: Bool {
        self == .overlay
    }

    var dismissesAfterSelection: Bool {
        self == .overlay
    }
}

/// Slide-over sidebar showing server info and tmux sessions/windows.
///
/// Layout matches the design mockup:
/// - Server card at top (name, status, Switch Host / Disconnect)
/// - Flat session labels (uppercase, always expanded) with windows
/// - Footer with + Window / + Session buttons
/// - Long-press context menus on sessions and windows
struct TmuxSidebarView: View {
    @Environment(ShellCoordinator.self) private var coordinator

    let presentation: TmuxSidebarPresentation
    let onDismiss: (() -> Void)?
    let onDisconnect: () -> Void
    let onSwitchHost: () -> Void

    @State private var renameTarget: TmuxSession?
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 0) {
            ServerCardView(
                server: coordinator.activeServer,
                showsDismissButton: presentation.showsDismissButton,
                onSwitchHost: onSwitchHost,
                onDisconnect: onDisconnect,
                onDismiss: { onDismiss?() }
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
        .alert(String(localized: "Rename Session"), isPresented: showRenameAlert) {
            TextField(String(localized: "Session name"), text: $renameText)
            Button(String(localized: "Cancel"), role: .cancel) { }
            Button(String(localized: "Rename")) {
                if let session = renameTarget, !renameText.isEmpty {
                    coordinator.renameTmuxSession(session.name, to: renameText)
                }
            }
        }
    }

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
                            dismissIfNeeded()
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
                                dismissIfNeeded()
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

            Text(String(localized: "No tmux sessions"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.25))

            Text(String(localized: "Start tmux to manage\nwindows from here."))
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.15))
                .multilineTextAlignment(.center)

            Button {
                coordinator.newTmuxSession()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                    Text(String(localized: "New Session"))
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

    private var showRenameAlert: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    private func dismissIfNeeded() {
        guard presentation.dismissesAfterSelection else { return }
        onDismiss?()
    }
}
#endif
