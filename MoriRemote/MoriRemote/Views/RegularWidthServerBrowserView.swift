import Observation
import SwiftUI

@MainActor
@Observable
final class RegularWidthServerSelection {
    var selectedServerID: Server.ID?
    private(set) var lastFocusedServerID: Server.ID?

    func selectedServer(in servers: [Server]) -> Server? {
        guard let selectedServerID else { return nil }
        return servers.first(where: { $0.id == selectedServerID })
    }

    func select(_ server: Server?) {
        selectedServerID = server?.id
        if let serverID = server?.id {
            lastFocusedServerID = serverID
        }
    }

    func remember(_ server: Server?) {
        guard let serverID = server?.id else { return }
        lastFocusedServerID = serverID
        if selectedServerID == nil {
            selectedServerID = serverID
        }
    }

    func reconcile(with servers: [Server], preferredServer: Server? = nil) {
        if let selectedServerID,
           servers.contains(where: { $0.id == selectedServerID }) {
            return
        }

        if let preferredServer,
           servers.contains(where: { $0.id == preferredServer.id }) {
            selectedServerID = preferredServer.id
            lastFocusedServerID = preferredServer.id
            return
        }

        if let lastFocusedServerID,
           servers.contains(where: { $0.id == lastFocusedServerID }) {
            selectedServerID = lastFocusedServerID
            return
        }

        selectedServerID = nil
    }
}

private enum RegularWidthServerDetailState {
    case empty
    case placeholder
    case selected(Server)
    case connecting(Server)
    case failure(Server, String)
}

struct RegularWidthServerBrowserView: View {
    @Environment(ServerStore.self) private var store
    @Environment(ShellCoordinator.self) private var coordinator

    let selection: RegularWidthServerSelection

    @State private var editingServer: Server?
    @State private var showingAddSheet = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detail
                .background(Theme.bg.ignoresSafeArea())
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingAddSheet) {
            ServerFormView(mode: .add) { server in
                store.add(server)
                selection.select(server)
            }
        }
        .sheet(item: $editingServer) { server in
            ServerFormView(mode: .edit(server)) { updated in
                store.update(updated)
                selection.select(updated)
                clearFailureIfShowing(serverID: updated.id)
            }
        }
        .onAppear {
            selection.remember(coordinator.activeServer)
            syncSelection(preferredServer: coordinator.activeServer)
        }
        .onChange(of: store.servers) { _, servers in
            selection.reconcile(with: servers, preferredServer: coordinator.activeServer)
        }
        .onChange(of: coordinator.state) { _, state in
            if state == .connecting || state == .shell || state == .connected {
                selection.remember(coordinator.activeServer)
                selection.select(coordinator.activeServer)
            }
            if state == .disconnected {
                selection.remember(coordinator.activeServer)
                syncSelection(preferredServer: coordinator.activeServer)
            }
        }
        .onChange(of: coordinator.lastError != nil) { _, _ in
            syncSelection(preferredServer: coordinator.activeServer)
        }
    }

    private var sidebar: some View {
        ZStack {
            Theme.sidebarBg.ignoresSafeArea()

            ServerListContentView(
                servers: store.servers,
                selectedServerID: selection.selectedServerID,
                connectingServerID: connectingServerID,
                onSelect: handleSidebarSelection,
                onAdd: { showingAddSheet = true },
                onEdit: { editingServer = $0 },
                onDelete: handleDelete
            )
        }
        .navigationTitle(String(localized: "Servers"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 32, height: 32)
                        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.rowRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.rowRadius)
                                .strokeBorder(Theme.accentBorder, lineWidth: 1)
                        )
                }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch detailState {
        case .empty:
            ServerBrowserInfoState(
                icon: "server.rack",
                title: String(localized: "No Servers"),
                message: String(localized: "Add a server to start browsing your remote workspaces on iPad."),
                actionTitle: String(localized: "Add Server"),
                actionSystemImage: "plus",
                action: { showingAddSheet = true }
            )

        case .placeholder:
            ServerBrowserInfoState(
                icon: "sidebar.left",
                title: String(localized: "Select a Server"),
                message: String(localized: "Choose a server from the sidebar to review its connection details before connecting."),
                actionTitle: nil,
                actionSystemImage: nil,
                action: nil
            )

        case .selected(let server):
            ServerBrowserSelectedDetail(
                server: server,
                canConnect: coordinator.state == .disconnected,
                onConnect: { connect(to: server) },
                onEdit: { editingServer = server }
            )

        case .connecting(let server):
            ServerBrowserConnectingDetail(server: server)

        case .failure(let server, let message):
            ServerBrowserFailureDetail(
                server: server,
                message: message,
                onRetry: { connect(to: server) },
                onEdit: { editingServer = server }
            )
        }
    }

    private var connectingServerID: Server.ID? {
        coordinator.state == .connecting ? coordinator.activeServer?.id : nil
    }

    private var detailState: RegularWidthServerDetailState {
        if store.servers.isEmpty {
            return .empty
        }

        if let connectingServer = connectingServer {
            return .connecting(connectingServer)
        }

        if let failure = failureContext {
            return .failure(failure.server, failure.message)
        }

        if let server = selection.selectedServer(in: store.servers) {
            return .selected(server)
        }

        return .placeholder
    }

    private var connectingServer: Server? {
        coordinator.state == .connecting ? coordinator.activeServer : nil
    }

    private var failureContext: (server: Server, message: String)? {
        guard coordinator.state == .disconnected,
              let server = coordinator.activeServer,
              let error = coordinator.lastError,
              selection.selectedServerID == server.id else {
            return nil
        }

        return (server, error.localizedDescription)
    }

    private func handleSidebarSelection(_ server: Server) {
        selection.select(server)

        if coordinator.activeServer?.id != server.id {
            coordinator.lastError = nil
        }
    }

    private func handleDelete(_ server: Server) {
        if selection.selectedServerID == server.id {
            selection.selectedServerID = nil
        }
        if coordinator.activeServer?.id == server.id {
            coordinator.lastError = nil
        }
        store.delete(server)
        syncSelection(preferredServer: coordinator.activeServer)
    }

    private func connect(to server: Server) {
        guard coordinator.state == .disconnected else { return }
        selection.remember(server)
        selection.select(server)
        coordinator.lastError = nil
        Task { await coordinator.connect(server: server) }
    }

    private func clearFailureIfShowing(serverID: Server.ID) {
        if coordinator.activeServer?.id == serverID {
            coordinator.lastError = nil
        }
    }

    private func syncSelection(preferredServer: Server?) {
        selection.reconcile(with: store.servers, preferredServer: preferredServer)
    }
}

private struct ServerBrowserInfoState: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let actionSystemImage: String?
    let action: (() -> Void)?

    var body: some View {
        ServerBrowserDetailLayout {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.accent)

                Text(title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let actionTitle, let actionSystemImage, let action {
                    Button(action: action) {
                        Label(actionTitle, systemImage: actionSystemImage)
                    }
                    .buttonStyle(Theme.PrimaryButtonStyle())
                    .frame(maxWidth: 220)
                    .padding(.top, 4)
                }
            }
            .cardStyle(padding: 24)
        }
    }
}

private struct ServerBrowserSelectedDetail: View {
    let server: Server
    let canConnect: Bool
    let onConnect: () -> Void
    let onEdit: () -> Void

    var body: some View {
        ServerBrowserDetailLayout {
            VStack(alignment: .leading, spacing: 16) {
                header
                actionRow
                connectionSection
                sessionSection
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Connection"))
                .moriSectionHeaderStyle()

            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .fill(canConnect ? Theme.accentSoft : Theme.mutedSurface)
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: "terminal")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(canConnect ? Theme.accent : Theme.textSecondary)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(server.displayName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    Text(server.subtitle)
                        .font(Theme.monoDetailFont)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer(minLength: 12)

                ConnectionBadge(
                    title: canConnect ? String(localized: "Ready to connect") : String(localized: "Connection busy"),
                    color: canConnect ? Theme.accent : Theme.textTertiary
                )
            }
        }
        .cardStyle(padding: 20)
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button(action: onConnect) {
                Label(String(localized: "Connect"), systemImage: "arrow.up.right.circle.fill")
            }
            .buttonStyle(Theme.PrimaryButtonStyle(disabled: !canConnect))
            .disabled(!canConnect)

            Button(action: onEdit) {
                Label(String(localized: "Edit"), systemImage: "pencil")
            }
            .buttonStyle(Theme.SecondaryButtonStyle())
        }
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "CONNECTION"))
                .moriSectionHeaderStyle()

            VStack(spacing: 0) {
                detailRow(label: String(localized: "Host"), value: server.host)
                detailDivider
                detailRow(label: String(localized: "Port"), value: String(server.port), useMonospace: true)
                detailDivider
                detailRow(label: String(localized: "Username"), value: server.username, useMonospace: true)
            }
            .cardStyle(padding: 0)
        }
    }

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "TMUX SESSION"))
                .moriSectionHeaderStyle()

            VStack(spacing: 0) {
                detailRow(label: String(localized: "Default Session"), value: server.defaultSession, useMonospace: true)
                detailDivider
                detailNote(canConnect
                    ? String(localized: "Review the server settings, then connect when you're ready.")
                    : String(localized: "A connection is already in progress. Finish or cancel it before starting another one."))
            }
            .cardStyle(padding: 0)
        }
    }

    private var detailDivider: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(height: 1)
    }

    private func detailRow(label: String, value: String, useMonospace: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            Spacer(minLength: 12)

            Text(value)
                .font(useMonospace ? Theme.monoDetailFont : .system(size: 14))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func detailNote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
    }
}

private struct ServerBrowserConnectingDetail: View {
    let server: Server

    var body: some View {
        ServerBrowserDetailLayout {
            VStack(alignment: .leading, spacing: 16) {
                Text(String(localized: "Connection"))
                    .moriSectionHeaderStyle()

                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 14) {
                        RoundedRectangle(cornerRadius: Theme.cardRadius)
                            .fill(Theme.accentSoft)
                            .frame(width: 42, height: 42)
                            .overlay {
                                ProgressView()
                                    .tint(Theme.accent)
                            }

                        VStack(alignment: .leading, spacing: 6) {
                            WorkflowStateBadge(
                                title: String(localized: "Connecting…"),
                                color: Theme.accent,
                                background: Theme.accentSoft,
                                border: Theme.accentBorder
                            )

                            Text(String(localized: "Connecting to Server"))
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)

                            Text(server.displayName)
                                .font(Theme.rowTitleFont)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }

                    WorkflowMetadataBlock(server: server)

                    Text(String(localized: "Checking credentials and opening the SSH session. You can keep browsing servers while this attempt finishes."))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .cardStyle(padding: 20)
            }
        }
    }
}

private struct ServerBrowserFailureDetail: View {
    let server: Server
    let message: String
    let onRetry: () -> Void
    let onEdit: () -> Void

    var body: some View {
        ServerBrowserDetailLayout {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 14) {
                        RoundedRectangle(cornerRadius: Theme.cardRadius)
                            .fill(Theme.warning.opacity(0.12))
                            .frame(width: 42, height: 42)
                            .overlay {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Theme.warning)
                            }

                        VStack(alignment: .leading, spacing: 6) {
                            WorkflowStateBadge(
                                title: String(localized: "Connection Failed"),
                                color: Theme.warning,
                                background: Theme.warning.opacity(0.12),
                                border: Theme.warning.opacity(0.24)
                            )

                            Text(server.displayName)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)

                            Text(server.subtitle)
                                .font(Theme.monoDetailFont)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }

                    WorkflowMetadataBlock(server: server)
                }
                .cardStyle(padding: 20)

                VStack(alignment: .leading, spacing: 10) {
                    Label(String(localized: "SSH couldn’t connect with the current settings."), systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.warning)

                    Text(message)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .background(Theme.mutedSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius)
                        .strokeBorder(Theme.cardBorder, lineWidth: 1)
                )

                HStack(spacing: 12) {
                    Button(action: onRetry) {
                        Label(String(localized: "Retry"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(Theme.PrimaryButtonStyle())

                    Button(action: onEdit) {
                        Label(String(localized: "Edit Server"), systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(Theme.SecondaryButtonStyle())
                }
            }
        }
    }
}

private struct WorkflowMetadataBlock: View {
    let server: Server

    var body: some View {
        VStack(spacing: 0) {
            metadataRow(label: String(localized: "Host"), value: server.host)
            metadataDivider
            metadataRow(label: String(localized: "Username"), value: server.username, monospace: true)
            metadataDivider
            metadataRow(label: String(localized: "Session"), value: server.defaultSession, monospace: true)
        }
        .background(Theme.mutedSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.cardBorder, lineWidth: 1)
        )
    }

    private var metadataDivider: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(height: 1)
    }

    private func metadataRow(label: String, value: String, monospace: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            Spacer(minLength: 10)

            Text(value)
                .font(monospace ? Theme.monoDetailFont : .system(size: 13))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct WorkflowStateBadge: View {
    let title: String
    let color: Color
    let background: Color
    let border: Color

    var body: some View {
        Text(title)
            .font(Theme.shortcutFont.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(background, in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(border, lineWidth: 1)
            )
    }
}

private struct ServerBrowserDetailLayout<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}

private struct ConnectionBadge: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text(title)
                .font(Theme.shortcutFont)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.mutedSurface, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.cardBorder, lineWidth: 1)
        )
    }
}
