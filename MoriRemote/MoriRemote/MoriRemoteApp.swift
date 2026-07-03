import SwiftUI

@main
struct MoriRemoteApp: App {
    @State private var coordinator = ShellCoordinator()
    @State private var store = ServerStore()
    @State private var regularWidthSelection = RegularWidthServerSelection()
    @State private var terminalSessionHost = TerminalSessionHost()

    var body: some Scene {
        WindowGroup {
            RootView(
                regularWidthSelection: regularWidthSelection,
                terminalSessionHost: terminalSessionHost
            )
            .environment(coordinator)
            .environment(store)
        }
    }
}

private struct RootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(ShellCoordinator.self) private var coordinator
    @Environment(ServerStore.self) private var store
    @State private var showsCompactTerminal = false
    @State private var renameTarget: TmuxSession?
    @State private var renameText = ""

    let regularWidthSelection: RegularWidthServerSelection
    let terminalSessionHost: TerminalSessionHost

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularWidthContent
            } else {
                compactContent
            }
        }
        .animation(.easeInOut(duration: 0.25), value: coordinator.state)
        .onAppear {
            terminalSessionHost.handleCoordinatorStateChange(
                coordinator.state,
                activeServerID: coordinator.activeServer?.id
            )
        }
        .onChange(of: coordinator.state) { _, newState in
            if newState == .disconnected || newState == .connecting {
                showsCompactTerminal = false
            } else if newState == .shell, let serverID = coordinator.activeServer?.id {
                store.markConnected(serverID)
            }
            terminalSessionHost.handleCoordinatorStateChange(
                newState,
                activeServerID: coordinator.activeServer?.id
            )
        }
        .onChange(of: coordinator.activeServer?.id) { _, newServerID in
            regularWidthSelection.remember(coordinator.activeServer)
            terminalSessionHost.handleCoordinatorStateChange(
                coordinator.state,
                activeServerID: newServerID
            )
        }
    }

    @ViewBuilder
    private var compactContent: some View {
        switch coordinator.state {
        case .disconnected, .connecting:
            ServerListView()

        case .connected:
            terminalContent

        case .shell:
            compactWorkspace
        }
    }

    @ViewBuilder
    private var regularWidthContent: some View {
        switch coordinator.state {
        case .disconnected, .connecting:
            RegularWidthServerBrowserView(selection: regularWidthSelection)

        case .connected, .shell:
            terminalContent
        }
    }

    private var compactWorkspace: some View {
        NavigationStack {
            if let server = coordinator.activeServer {
                WorkspaceView(
                    serverName: server.displayName,
                    sessions: coordinator.tmuxSessions,
                    activeSessionName: coordinator.tmuxActiveSession?.name,
                    activeWindowID: coordinator.tmuxActiveSession?.windows.first(where: { $0.isActive })?.id,
                    showsDismissButton: false,
                    onSelectWindow: { session, windowIndex in
                        coordinator.selectTmuxWindow(session: session, windowIndex: windowIndex)
                        showsCompactTerminal = true
                    },
                    onSelectPane: { session, windowIndex, paneId in
                        coordinator.selectTmuxPane(session: session, windowIndex: windowIndex, paneId: paneId)
                        showsCompactTerminal = true
                    },
                    onSwitchSession: { session in coordinator.switchTmuxSession(session) },
                    onRenameSession: { session in
                        renameTarget = session
                        renameText = session.name
                    },
                    onKillSession: { session in coordinator.closeTmuxSession(session) },
                    onNewWindowAfter: { session, windowIndex in
                        coordinator.newTmuxWindowAfter(session: session, windowIndex: windowIndex)
                    },
                    onCloseWindow: { session, windowIndex in
                        coordinator.closeTmuxWindow(session: session, windowIndex: windowIndex)
                    },
                    onNewWindow: { coordinator.newTmuxWindow() },
                    onNewSession: { coordinator.newTmuxSession() },
                    onSwitchHost: returnToDisconnectedBrowser,
                    onDisconnect: returnToDisconnectedBrowser,
                    onDismiss: nil,
                    onRefresh: { coordinator.refreshTmuxState() }
                )
                .navigationBarHidden(true)
                .alert(String(localized: "Rename Session"), isPresented: showRenameAlert) {
                    TextField(String(localized: "Session name"), text: $renameText)
                    Button(String(localized: "Cancel"), role: .cancel) { }
                    Button(String(localized: "Rename")) {
                        if let session = renameTarget, !renameText.isEmpty {
                            coordinator.renameTmuxSession(session.name, to: renameText)
                        }
                    }
                }
                .navigationDestination(isPresented: $showsCompactTerminal) {
                    TerminalScreen(
                        sessionHost: terminalSessionHost,
                        serverName: server.displayName,
                        onDisconnect: returnToDisconnectedBrowser,
                        onSwitchHost: returnToDisconnectedBrowser,
                        onBackToWorkspace: { showsCompactTerminal = false }
                    )
                    .navigationBarHidden(true)
                }
            } else {
                ServerListView()
            }
        }
    }

    @ViewBuilder
    private var terminalContent: some View {
        if let server = coordinator.activeServer {
            TerminalScreen(
                sessionHost: terminalSessionHost,
                serverName: server.displayName,
                onDisconnect: returnToDisconnectedBrowser,
                onSwitchHost: returnToDisconnectedBrowser,
                onBackToWorkspace: { showsCompactTerminal = false }
            )
        } else if horizontalSizeClass == .regular {
            RegularWidthServerBrowserView(selection: regularWidthSelection)
        } else {
            ServerListView()
        }
    }

    private var showRenameAlert: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    private func returnToDisconnectedBrowser() {
        let activeServer = coordinator.activeServer
        regularWidthSelection.remember(activeServer)
        regularWidthSelection.select(activeServer)
        Task { await coordinator.disconnect() }
    }
}

extension String {
    static func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key)
    }
}
