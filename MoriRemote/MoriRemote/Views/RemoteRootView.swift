import SwiftUI
import UIKit

@MainActor
struct RemoteRootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
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
            } else if sizeClass == .regular {
                regularLayout
            } else if let runtime = root.activeRuntime {
                RemoteTerminalView(root: root, runtime: runtime, compact: true, showLibrary: { sheet = .library })
            } else {
                NavigationStack { library }
            }
        }
        .tint(.mint)
        .task { root.bootstrap() }
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

    private var regularLayout: some View {
        NavigationSplitView {
            library
                .navigationTitle(String(localized: "Library"))
        } detail: {
            if let runtime = root.activeRuntime {
                RemoteTerminalView(root: root, runtime: runtime, compact: false, showLibrary: {})
            } else {
                ContentUnavailableView(
                    String(localized: "Select a workspace"),
                    systemImage: "rectangle.split.3x1",
                    description: Text(String(localized: "Choose a saved workspace to open its terminal."))
                )
            }
        }
    }

    private var library: some View {
        RemoteLibraryView(
            servers: root.servers,
            workspaces: root.workspaces,
            activeWorkspaceIDs: Set(root.activeWorkspaces.map(\.id)),
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
                                if activeWorkspaceIDs.contains(workspace.id) { Image(systemName: "dot.radiowaves.left.and.right") }
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

@MainActor
private struct RemoteTerminalView: View {
    let root: RemoteRootModel
    let runtime: ActiveWorkspaceRuntime
    let compact: Bool
    let showLibrary: () -> Void
    @State private var showsPanes = false
    @State private var confirmsClosePane = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if let surface = runtime.surface() {
                TmuxPaneSurfaceView(surface: surface)
                    .id(runtime.instanceID)
                    .background(Color.black)
            } else {
                ContentUnavailableView(runtime.status.title, systemImage: "terminal", description: Text(String(localized: "Waiting for the active tmux pane.")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showsPanes) { panePicker }
        .onChange(of: root.runtimeRevision) { _, _ in }
        .confirmationDialog(String(localized: "Close shared pane?"), isPresented: $confirmsClosePane, titleVisibility: .visible) {
            Button(String(localized: "Close pane"), role: .destructive) { root.closePane() }
        } message: {
            Text(String(localized: "Closing this shared pane affects every tmux client."))
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if compact {
                Button(action: dismissKeyboard) { Image(systemName: "keyboard.chevron.compact.down") }
                    .accessibilityLabel(String(localized: "Dismiss keyboard"))
                Button(action: showLibrary) { Image(systemName: "sidebar.left") }
                    .accessibilityLabel(String(localized: "Show library"))
            }
            Button { showsPanes = true } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: runtime.topology?.sessionName ?? runtime.workspace.name)
                        .lineLimit(1)
                    Text(runtime.status.title).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Menu {
                Button(String(localized: "Split right (shared)")) { root.split(horizontal: true) }
                Button(String(localized: "Split down (shared)")) { root.split(horizontal: false) }
                Button(String(localized: "New window (shared)")) { root.newWindow() }
                Button(String(localized: "Close pane (shared)"), role: .destructive) { confirmsClosePane = true }
            } label: { Image(systemName: "rectangle.3.group") }
            Button(action: copySelection) { Image(systemName: "doc.on.doc") }
                .accessibilityLabel(String(localized: "Copy selection"))
            Button(action: root.disconnectActive) { Image(systemName: "power") }
                .accessibilityLabel(String(localized: "Disconnect"))
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .foregroundStyle(.white)
        .background(Color(white: 0.12))
    }

    private var panePicker: some View {
        NavigationStack {
            List {
                Section(String(localized: "Windows")) {
                    ForEach(runtime.topology?.windows ?? [], id: \.id) { window in
                        Button { root.selectWindow(window.id) } label: {
                            Label {
                                Text(verbatim: window.name)
                            } icon: {
                                Image(systemName: window.active ? "rectangle.inset.filled" : "rectangle")
                            }
                        }
                    }
                }
                Section(String(localized: "Panes")) {
                    ForEach(runtime.topology?.panes ?? [], id: \.id) { pane in
                        Button {
                            root.selectPane(pane.id)
                            showsPanes = false
                        } label: {
                            HStack {
                                Text(verbatim: "%\(pane.id.rawValue)")
                                    .font(.body.monospaced())
                                Spacer()
                                Text(verbatim: "\(pane.width)×\(pane.height)")
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

    private func dismissKeyboard() { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
    private func copySelection() { if let text = runtime.surface()?.copySelection(), !text.isEmpty { UIPasteboard.general.string = text } }
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
