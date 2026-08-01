import SwiftUI
import UIKit
import MoriRemoteTerminal

@MainActor
struct RemoteRootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    let root: RemoteRootModel
    @State private var sheet: RemoteSheet?
    @State private var pendingConfirmation: RemoteDestructiveAction?

    var body: some View {
        Group {
            if let error = root.libraryLoadError {
                VStack(spacing: 16) {
                    ContentUnavailableView(
                        String(localized: "Library unavailable"),
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                    Button(String(localized: "Retry"), action: root.bootstrap)
                }
            } else if !root.isLoaded {
                ProgressView(String(localized: "Loading library…"))
            } else {
                adaptiveLayout
            }
        }
        .tint(.mint)
        .task { root.bootstrap() }
        .onChange(of: scenePhase) { _, phase in
            root.scenePhaseChanged(phase)
        }
        .sheet(item: $sheet) { route in
            switch route {
            case .add:
                ProfileEditorView(draft: .init()) { root.save($0) }
            case let .edit(serverID):
                if let server = root.servers.first(where: { $0.id == serverID }) {
                    ProfileEditorView(
                        draft: .init(server: server, identity: root.identities.first(where: { $0.id == server.identityID })),
                        existingServer: server,
                        onSave: { root.save($0, existingServer: server) }
                    )
                }
            case .settings:
                RemoteSettingsView(settings: root.settings, onSave: root.save(settings:))
            case let .workspace(serverID, workspaceID):
                WorkspaceEditorView(
                    draft: .init(serverID: serverID, workspace: workspaceID.flatMap { id in root.workspaces.first { $0.id == id } }),
                    onSave: root.save
                )
            case .library:
                NavigationStack { library }
            }
        }
        .confirmationDialog(String(localized: "Confirm destructive action"), isPresented: destructiveConfirmationBinding, titleVisibility: .visible) {
            if let action = pendingConfirmation {
                switch action {
                case let .server(server, _):
                    Button(String(localized: "Delete"), role: .destructive) { root.delete(server); pendingConfirmation = nil }
                case let .workspace(workspace):
                    Button(String(localized: "Delete"), role: .destructive) { root.delete(workspace: workspace); pendingConfirmation = nil }
                }
            }
        } message: {
            Text(pendingConfirmation?.message ?? "")
        }
        .alert(String(localized: "Host key confirmation"), isPresented: trustBinding, presenting: root.pendingTrust) { challenge in
            Button(challenge.kind == .changed ? String(localized: "Replace trusted key") : String(localized: "Trust host key"), role: challenge.kind == .changed ? .destructive : nil) {
                root.confirmTrust(challenge, replaceChanged: challenge.kind == .changed)
            }
            Button(String(localized: "Cancel"), role: .cancel) { root.dismissTrust() }
        } message: { challenge in
            Text(challengeMessage(challenge))
        }
        .alert(String(localized: "Connection Failed"), isPresented: errorBinding) {
            Button(String(localized: "OK"), role: .cancel) { root.errorMessage = nil }
        } message: {
            Text(root.errorMessage ?? "")
        }
    }

    /// The terminal is always the trailing child. Size-class changes only add or
    /// remove the leading library, preserving the representable's surface,
    /// viewport, responder, and its runtime instance.
    private var adaptiveLayout: some View {
        HStack(spacing: 0) {
            if sizeClass == .regular {
                NavigationStack { library.navigationTitle(String(localized: "Library")) }
                    .frame(minWidth: 300, idealWidth: 360, maxWidth: 420)
                Divider()
            }
            terminalDetail
        }
    }

    @ViewBuilder private var terminalDetail: some View {
        if let runtime = root.activeRuntime {
            RemoteTerminalDetailView(root: root, runtime: runtime, compact: sizeClass == .compact, showLibrary: { sheet = .library })
        } else if sizeClass == .compact {
            NavigationStack { library }
        } else {
            ContentUnavailableView(
                String(localized: "Select a workspace"),
                systemImage: "rectangle.split.3x1",
                description: Text(String(localized: "Choose a saved workspace to open its terminal."))
            )
        }
    }

    private var library: some View {
        RemoteLibraryView(
            servers: root.servers,
            workspaces: root.workspaces,
            activeWorkspaceIDs: Set(root.activeWorkspaces.map(\.id)),
            agentSummaries: Dictionary(uniqueKeysWithValues: root.activeWorkspaces.map { ($0.id, root.agentSummary(for: $0.id)) }),
            migrationReport: root.migrationReport,
            onConnect: {
                root.connect(workspaceID: $0)
                if sizeClass == .compact { sheet = nil }
            },
            onAdd: { sheet = .add },
            onEdit: { sheet = .edit($0.id) },
            onDelete: { server in pendingConfirmation = .server(server, workspaceCount: root.workspaces.filter { $0.serverID == server.id }.count) },
            onAddWorkspace: { sheet = .workspace(serverID: $0, workspaceID: nil) },
            onEditWorkspace: { sheet = .workspace(serverID: $0.serverID, workspaceID: $0.id) },
            onDeleteWorkspace: { pendingConfirmation = .workspace($0) },
            onSettings: { sheet = .settings }
        )
    }

    private var destructiveConfirmationBinding: Binding<Bool> {
        .init(get: { pendingConfirmation != nil }, set: { if !$0 { pendingConfirmation = nil } })
    }
    private var trustBinding: Binding<Bool> {
        .init(get: { root.pendingTrust != nil }, set: { if !$0 { root.dismissTrust() } })
    }
    private var errorBinding: Binding<Bool> {
        .init(get: { root.errorMessage != nil }, set: { if !$0 { root.errorMessage = nil } })
    }
    private func challengeMessage(_ challenge: SSHHostTrustChallenge) -> String {
        let prior = challenge.trustedFingerprint.map { "\n\n\(String(localized: "Previously trusted:")) \($0)" } ?? ""
        return "\(challenge.endpoint.host):\(challenge.endpoint.port)\n\(challenge.algorithm)\n\(challenge.receivedFingerprint)\(prior)"
    }
}

private enum RemoteDestructiveAction: Identifiable {
    case server(SavedServer, workspaceCount: Int)
    case workspace(SavedWorkspace)

    var id: UUID {
        switch self {
        case let .server(server, _): server.id
        case let .workspace(workspace): workspace.id
        }
    }

    var message: String {
        switch self {
        case let .server(_, workspaceCount):
            String(format: String(localized: "Deleting this server also deletes %lld workspaces and their saved credentials."), workspaceCount)
        case .workspace:
            String(localized: "Deleting this workspace disconnects it and cannot be undone.")
        }
    }
}

private enum RemoteSheet: Identifiable {
    case add, edit(UUID), settings, workspace(serverID: UUID, workspaceID: UUID?), library
    var id: String {
        switch self {
        case .add: "add"
        case let .edit(id): "edit-\(id)"
        case .settings: "settings"
        case let .workspace(serverID, workspaceID): "workspace-\(serverID)-\(workspaceID?.uuidString ?? "new")"
        case .library: "library"
        }
    }
}

private struct RemoteLibraryView: View {
    let servers: [SavedServer]
    let workspaces: [SavedWorkspace]
    let activeWorkspaceIDs: Set<UUID>
    let agentSummaries: [UUID: AgentMetadata]
    let migrationReport: LegacyMigrationReport?
    let onConnect: (UUID) -> Void
    let onAdd: () -> Void
    let onEdit: (SavedServer) -> Void
    let onDelete: (SavedServer) -> Void
    let onAddWorkspace: (UUID) -> Void
    let onEditWorkspace: (SavedWorkspace) -> Void
    let onDeleteWorkspace: (SavedWorkspace) -> Void
    let onSettings: () -> Void
    @State private var filter = ""

    var body: some View {
        List {
            if let migrationReport, !migrationReport.records.isEmpty {
                Section(String(localized: "Migration")) {
                    Label(String(format: String(localized: "%lld saved profiles migrated"), migrationReport.records.filter { $0.disposition != .skippedInvalid }.count), systemImage: "checkmark.shield")
                        .foregroundStyle(.secondary)
                }
            }
            if filteredServers.isEmpty {
                ContentUnavailableView(
                    filter.isEmpty ? String(localized: "No saved servers") : String(localized: "No matching workspaces"),
                    systemImage: "server.rack",
                    description: Text(String(localized: "Add a server and workspace to begin."))
                )
                .listRowBackground(Color.clear)
            }
            ForEach(filteredServers) { server in
                Section {
                    ForEach(workspaces.filter { $0.serverID == server.id && matches($0) }) { workspace in
                        Button { onConnect(workspace.id) } label: {
                            HStack {
                                Image(systemName: activeWorkspaceIDs.contains(workspace.id) ? "terminal.fill" : "terminal")
                                    .foregroundStyle(activeWorkspaceIDs.contains(workspace.id) ? .mint : .secondary)
                                VStack(alignment: .leading) {
                                    Text(verbatim: workspace.name)
                                    Text(verbatim: workspace.tmuxSession)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let summary = agentSummaries[workspace.id], summary.state != .unknown {
                                    AgentMetadataBadge(metadata: summary)
                                } else if activeWorkspaceIDs.contains(workspace.id) {
                                    Image(systemName: "dot.radiowaves.left.and.right")
                                }
                            }
                        }
                        .contextMenu {
                            Button(String(localized: "Edit workspace"), action: { onEditWorkspace(workspace) })
                            Button(String(localized: "Delete workspace"), role: .destructive, action: { onDeleteWorkspace(workspace) })
                        }
                    }
                    Button(String(localized: "Add workspace"), systemImage: "plus") { onAddWorkspace(server.id) }
                } header: {
                    HStack {
                        Text(verbatim: server.name)
                        Spacer()
                        Text(verbatim: "\(server.username)@\(server.host)")
                    }
                }
                .contextMenu {
                    Button(String(localized: "Edit server"), action: { onEdit(server) })
                    Button(String(localized: "Delete server"), role: .destructive, action: { onDelete(server) })
                }
            }
        }
        .searchable(text: $filter, prompt: String(localized: "Filter servers and workspaces"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button(String(localized: "Settings"), systemImage: "gear", action: onSettings) }
            ToolbarItem(placement: .topBarTrailing) { Button(String(localized: "Add server"), systemImage: "plus", action: onAdd) }
        }
    }

    private var filteredServers: [SavedServer] {
        servers.filter { server in workspaces.contains { $0.serverID == server.id && matches($0) } }
    }
    private func matches(_ workspace: SavedWorkspace) -> Bool {
        filter.isEmpty || workspace.name.localizedCaseInsensitiveContains(filter) || workspace.tmuxSession.localizedCaseInsensitiveContains(filter) || servers.first(where: { $0.id == workspace.serverID })?.name.localizedCaseInsensitiveContains(filter) == true
    }
}

private struct AgentMetadataBadge: View {
    let metadata: AgentMetadata

    var body: some View {
        if metadata.state != .unknown {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                if let name = metadata.name { Text(verbatim: name).lineLimit(1) }
                Text(stateTitle).lineLimit(1)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
        }
    }

    private var symbol: String {
        switch metadata.state {
        case .working: "bolt.fill"
        case .waiting: "exclamationmark.circle.fill"
        case .done: "checkmark.circle.fill"
        case .unknown: "questionmark.circle"
        }
    }
    private var color: Color {
        switch metadata.state {
        case .working: .mint
        case .waiting: .orange
        case .done: .green
        case .unknown: .secondary
        }
    }
    private var stateTitle: String {
        switch metadata.state {
        case .working: String(localized: "Working")
        case .waiting: String(localized: "Waiting")
        case .done: String(localized: "Done")
        case .unknown: String(localized: "Unknown")
        }
    }
}

@MainActor
private struct RemoteTerminalDetailView: View {
    let root: RemoteRootModel
    let runtime: ActiveWorkspaceRuntime
    let compact: Bool
    let showLibrary: () -> Void
    @State private var showsSessions = false
    @State private var showsPanes = false
    @State private var pendingSharedMutation: RemoteSharedMutation?

    var body: some View {
        VStack(spacing: 0) {
            header
            MoriRemoteTerminalView(session: runtime.session, onShowSessions: { showsSessions = true })
                .id(WorkspaceTerminalPresentation.identity(for: runtime.session.instanceID))
                .background(Color.black)
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showsSessions) { sessionSwitcher }
        .sheet(isPresented: $showsPanes) { panePicker }
        .confirmationDialog(
            String(localized: "Confirm shared workspace change"),
            isPresented: sharedMutationConfirmationBinding,
            titleVisibility: .visible
        ) {
            if let mutation = pendingSharedMutation {
                Button(mutation.title, role: mutation.isDestructive ? .destructive : nil) {
                    root.performSharedMutation(mutation.value)
                    pendingSharedMutation = nil
                }
            }
        } message: {
            Text(String(localized: "This change affects every tmux client."))
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if compact {
                Button(action: showLibrary) { Image(systemName: "sidebar.left") }
                    .accessibilityLabel(String(localized: "Show library"))
            }
            Button { showsPanes = true } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: runtime.workspace.name).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(runtime.status.title).font(.caption).foregroundStyle(.secondary)
                        AgentMetadataBadge(metadata: runtime.metadata(for: runtime.focusedPaneID ?? 0))
                    }
                }
            }
            Spacer()
            Menu {
                Button(String(localized: "Split right (shared)")) { pendingSharedMutation = .splitHorizontal }
                Button(String(localized: "Split down (shared)")) { pendingSharedMutation = .splitVertical }
                Button(String(localized: "New window (shared)")) { pendingSharedMutation = .newWindow }
                Button(String(localized: "Close pane (shared)"), role: .destructive) { pendingSharedMutation = .closePane }
                Button(String(localized: "Close window (shared)"), role: .destructive) { pendingSharedMutation = .closeWindow }
            } label: { Image(systemName: "rectangle.3.group") }
            Button(action: root.disconnectActive) { Image(systemName: "power") }
                .accessibilityLabel(String(localized: "Disconnect"))
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .foregroundStyle(.white)
        .background(Color(white: 0.12))
    }

    private var sharedMutationConfirmationBinding: Binding<Bool> {
        .init(get: { pendingSharedMutation != nil }, set: { if !$0 { pendingSharedMutation = nil } })
    }

    private var sessionSwitcher: some View {
        NavigationStack {
            ActiveSessionSwitcherView(
                sessions: root.activeWorkspaces.map { workspace in
                    let activeRuntime = root.runtimes[workspace.id]
                    return ActiveSessionSwitcherItem(
                        id: workspace.id,
                        sessionName: workspace.name,
                        subtitle: activeRuntime?.status.title ?? String(localized: "Disconnected"),
                        isSelected: workspace.id == root.activeWorkspaceID,
                        lastOpenedAt: workspace.lastConnectedAt ?? .distantPast
                    )
                },
                onSelectSession: { root.connect(workspaceID: $0) },
                onDisconnectSession: { workspaceID in
                    Task { await root.disconnect(workspaceID: workspaceID) }
                }
            )
            .navigationTitle(String(localized: "Active workspaces"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Done")) { showsSessions = false }
                }
            }
        }
    }

    private var panePicker: some View {
        NavigationStack {
            List {
                Section(String(localized: "Windows")) {
                    ForEach(runtime.topology?.windows ?? []) { window in
                        Button { root.selectWindow(window.id) } label: {
                            HStack {
                                Label {
                                    Text(verbatim: window.title)
                                } icon: {
                                    Image(systemName: window.active ? "rectangle.inset.filled" : "rectangle")
                                }
                                Spacer()
                                AgentMetadataBadge(metadata: windowMetadata(window))
                            }
                        }
                    }
                }
                Section(String(localized: "Panes")) {
                    ForEach(runtime.topology?.panes ?? []) { pane in
                        Button {
                            root.selectPane(pane.id)
                            showsPanes = false
                        } label: {
                            HStack {
                                Text(verbatim: "%\(pane.id)")
                                    .font(.body.monospaced())
                                AgentMetadataBadge(metadata: runtime.metadata(for: pane.id))
                                Spacer()
                                Text(verbatim: "\(pane.columns)×\(pane.rows)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Workspace controls"))
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(String(localized: "Done")) { showsPanes = false } } }
        }
    }

    private func windowMetadata(_ window: MoriRemoteTerminalWindow) -> AgentMetadata {
        runtime.topology?.panes
            .filter { $0.windowID == window.id }
            .map { runtime.metadata(for: $0.id) }
            .max { $0.state.priority < $1.state.priority } ?? .unknown
    }
}

private enum RemoteSharedMutation: Identifiable, Equatable {
    case newWindow, splitHorizontal, splitVertical, closePane, closeWindow

    var id: Self { self }
    var value: MoriRemoteTerminalSharedMutation {
        switch self {
        case .newWindow: .newWindow
        case .splitHorizontal: .splitHorizontal
        case .splitVertical: .splitVertical
        case .closePane: .closePane
        case .closeWindow: .closeWindow
        }
    }
    var title: String {
        switch self {
        case .newWindow: String(localized: "New window (shared)")
        case .splitHorizontal: String(localized: "Split right (shared)")
        case .splitVertical: String(localized: "Split down (shared)")
        case .closePane: String(localized: "Close pane (shared)")
        case .closeWindow: String(localized: "Close window (shared)")
        }
    }
    var isDestructive: Bool { self == .closePane || self == .closeWindow }
}

private struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ServerWorkspaceDraft
    let existingServer: SavedServer?
    let onSave: (ServerWorkspaceDraft) -> Void

    init(draft: ServerWorkspaceDraft, existingServer: SavedServer? = nil, onSave: @escaping (ServerWorkspaceDraft) -> Void) {
        _draft = State(initialValue: draft)
        self.existingServer = existingServer
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Server")) {
                    TextField(String(localized: "Name"), text: $draft.serverName)
                    TextField(String(localized: "Host"), text: $draft.host)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField(String(localized: "Port"), text: $draft.port).keyboardType(.numberPad)
                    TextField(String(localized: "Username"), text: $draft.username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                if draft.workspaceID != nil {
                    Section(String(localized: "Workspace")) {
                        TextField(String(localized: "Workspace name"), text: $draft.workspaceName)
                        TextField(String(localized: "tmux session"), text: $draft.tmuxSession)
                    }
                }
                Section(String(localized: "Authentication")) {
                    Picker(String(localized: "Identity"), selection: $draft.identityKind) {
                        Text(String(localized: "Password")).tag(SSHIdentityKind.password)
                        Text(String(localized: "Private key")).tag(SSHIdentityKind.privateKey)
                    }
                    if draft.identityKind == .password {
                        SecureField(String(localized: "Password"), text: $draft.password)
                    } else {
                        TextEditor(text: $draft.privateKey).frame(minHeight: 110)
                        SecureField(String(localized: "Private key passphrase (optional)"), text: $draft.passphrase)
                    }
                }
            }
            .navigationTitle(String(localized: existingServer == nil ? "Add server" : "Edit server"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Cancel"), action: dismiss.callAsFunction) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) { onSave(draft); dismiss() }
                }
            }
        }
    }
}

private struct WorkspaceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WorkspaceDraft
    let onSave: (WorkspaceDraft) -> Void

    init(draft: WorkspaceDraft, onSave: @escaping (WorkspaceDraft) -> Void) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(String(localized: "Workspace name"), text: $draft.name)
                TextField(String(localized: "tmux session"), text: $draft.tmuxSession)
            }
            .navigationTitle(String(localized: "Workspace"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Cancel"), action: dismiss.callAsFunction) }
                ToolbarItem(placement: .confirmationAction) { Button(String(localized: "Save")) { onSave(draft); dismiss() } }
            }
        }
    }
}

private struct RemoteSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings: RemoteSettings
    let onSave: (RemoteSettings) -> Void

    init(settings: RemoteSettings, onSave: @escaping (RemoteSettings) -> Void) {
        _settings = State(initialValue: settings)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Terminal")) {
                    Stepper(String(format: String(localized: "Initial scrollback: %lld lines"), settings.initialScrollbackLines), value: $settings.initialScrollbackLines, in: RemoteSettings.minimumInitialScrollbackLines...RemoteSettings.maximumScrollbackLines, step: 500)
                    Text(String(localized: "Local history is limited to 10,000 lines; server copy-mode browsing stays disabled."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section(String(localized: "Security")) {
                    Toggle(String(localized: "Allow legacy RSA/SHA-1 authentication"), isOn: $settings.allowLegacyRSA)
                }
            }
            .navigationTitle(String(localized: "Settings"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Cancel"), action: dismiss.callAsFunction) }
                ToolbarItem(placement: .confirmationAction) { Button(String(localized: "Save")) { onSave(settings); dismiss() } }
            }
        }
    }
}
