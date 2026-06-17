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

/// Sidebar showing the active server and tmux sessions/windows.
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
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ServerCardView(
                        server: coordinator.activeServer,
                        showsDismissButton: onDismiss != nil,
                        onSwitchHost: onSwitchHost,
                        onDisconnect: onDisconnect,
                        onDismiss: { onDismiss?() }
                    )

                    VStack(alignment: .leading, spacing: 16) {
                        Text(String(localized: "Projects"))
                            .moriSectionHeaderStyle()
                            .padding(.horizontal, 16)

                        if coordinator.tmuxSessions.isEmpty {
                            emptyState
                        } else {
                            projectList
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 12)
                .padding(.bottom, 18)
            }

            if !coordinator.tmuxSessions.isEmpty {
                TmuxSidebarFooter(
                    onNewWindow: { coordinator.newTmuxWindow() },
                    onNewSession: { coordinator.newTmuxSession() }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.sidebarBg)
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

    /// Sessions grouped by mori project short name (the `<project>/<branch>`
    /// convention), preserving first-seen order.
    private var projectGroups: [(project: String, sessions: [TmuxSession])] {
        var order: [String] = []
        var map: [String: [TmuxSession]] = [:]
        for session in coordinator.tmuxSessions {
            let project = Self.projectName(for: session.name)
            if map[project] == nil { order.append(project) }
            map[project, default: []].append(session)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    private var projectList: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(projectGroups, id: \.project) { group in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                        Text(group.project)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, 14)

                    ForEach(group.sessions) { session in
                        sessionCard(session)
                    }
                }
            }
        }
    }

    private func sessionCard(_ session: TmuxSession) -> some View {
        let isActiveSession = session.name == coordinator.tmuxActiveSession?.name

        return VStack(spacing: 6) {
            TmuxSessionHeader(
                session: session,
                isActive: isActiveSession,
                branchLabel: Self.branchLabel(for: session.name),
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

            VStack(spacing: 4) {
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

                    if window.panes.count > 1 {
                        VStack(spacing: 2) {
                            ForEach(window.panes) { pane in
                                TmuxPaneRow(
                                    pane: pane,
                                    isHighlighted: isActiveSession && window.isActive && pane.isActive,
                                    onSelect: {
                                        coordinator.selectTmuxPane(
                                            session: session.name,
                                            windowIndex: window.index,
                                            paneId: pane.paneId
                                        )
                                        dismissIfNeeded()
                                    }
                                )
                            }
                        }
                        .padding(.leading, 30)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .cardStyle(padding: 0)
    }

    /// Project short name from a `<project>/<branch>` session name, else the
    /// whole name when it doesn't follow the convention.
    static func projectName(for sessionName: String) -> String {
        guard let slash = sessionName.firstIndex(of: "/") else { return sessionName }
        return String(sessionName[..<slash])
    }

    /// Branch slug from a `<project>/<branch>` session name, else nil.
    static func branchLabel(for sessionName: String) -> String? {
        guard let slash = sessionName.firstIndex(of: "/") else { return nil }
        let branch = sessionName[sessionName.index(after: slash)...]
        return branch.isEmpty ? nil : String(branch)
    }

    private var emptyState: some View {
        VStack(alignment: .center, spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)

            Text(String(localized: "No tmux sessions"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Text(String(localized: "Start tmux to manage\nwindows from here."))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                coordinator.newTmuxSession()
            } label: {
                Label(String(localized: "New Session"), systemImage: "plus")
            }
            .buttonStyle(Theme.SecondaryButtonStyle(
                foreground: Theme.accent,
                background: Theme.accentSoft,
                border: Theme.accentBorder
            ))
            .frame(maxWidth: 180)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 26)
        .cardStyle(padding: 20)
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
