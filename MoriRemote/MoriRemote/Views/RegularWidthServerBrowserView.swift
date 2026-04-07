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
            Theme.bg.ignoresSafeArea()

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
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch detailState {
        case .empty:
            ServerBrowserEmptyDetail(onAdd: { showingAddSheet = true })

        case .placeholder:
            ServerBrowserPlaceholderDetail()

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

private struct ServerBrowserEmptyDetail: View {
    let onAdd: () -> Void

    var body: some View {
        ServerBrowserDetailCard(icon: "server.rack", title: String(localized: "No Servers")) {
            Text(String(localized: "Add a server to start browsing your remote workspaces on iPad."))
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            Button(action: onAdd) {
                Label(String(localized: "Add Server"), systemImage: "plus")
            }
            .buttonStyle(Theme.PrimaryButtonStyle())
            .frame(maxWidth: 240)
        }
    }
}

private struct ServerBrowserPlaceholderDetail: View {
    var body: some View {
        ServerBrowserDetailCard(icon: "rectangle.and.hand.point.up.left.filled", title: String(localized: "Select a Server")) {
            Text(String(localized: "Choose a server from the sidebar to review its connection details before connecting."))
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
    }
}

private struct ServerBrowserSelectedDetail: View {
    let server: Server
    let canConnect: Bool
    let onConnect: () -> Void
    let onEdit: () -> Void

    var body: some View {
        ServerBrowserDetailCard(icon: "terminal", title: server.displayName) {
            VStack(spacing: 20) {
                statusSummary
                detailRows

                HStack(spacing: 12) {
                    Button(action: onConnect) {
                        Label(String(localized: "Connect"), systemImage: "arrow.up.right.circle.fill")
                    }
                    .buttonStyle(Theme.PrimaryButtonStyle(disabled: !canConnect))
                    .disabled(!canConnect)

                    Button(action: onEdit) {
                        Label(String(localized: "Edit"), systemImage: "pencil")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.buttonRadius)
                                    .strokeBorder(Theme.cardBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Text(canConnect
                    ? String(localized: "Review the server settings, then connect when you're ready.")
                    : String(localized: "A connection is already in progress. Finish or cancel it before starting another one."))
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            .frame(maxWidth: 440)
        }
    }

    private var statusSummary: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(canConnect ? Theme.accent : Theme.textTertiary)
                .frame(width: 10, height: 10)

            Text(canConnect ? String(localized: "Ready to connect") : String(localized: "Connection busy"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            Spacer()

            Text(server.subtitle)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.accent.opacity(canConnect ? 0.10 : 0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(canConnect ? Theme.accent.opacity(0.22) : Theme.cardBorder, lineWidth: 1)
        )
    }
 
    private var detailRows: some View {
        VStack(spacing: 0) {
            detailRow(label: String(localized: "Host"), value: server.host)
            divider
            detailRow(label: String(localized: "Port"), value: String(server.port))
            divider
            detailRow(label: String(localized: "Username"), value: server.username)
            divider
            detailRow(label: String(localized: "Default Session"), value: server.defaultSession)
        }
        .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.cardBorder, lineWidth: 1)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.cardBorder)
            .frame(height: 1)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(spacing: 16) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

private struct ServerBrowserConnectingDetail: View {
    let server: Server

    var body: some View {
        ServerBrowserDetailCard(icon: "bolt.horizontal.circle", title: String(localized: "Connecting…")) {
            VStack(spacing: 16) {
                ProgressView()
                    .tint(Theme.accent)
                    .scaleEffect(1.2)

                Text(server.displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text(server.subtitle)
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)

                Text(String(localized: "MoriRemote is opening the SSH connection. You can keep browsing servers while this attempt finishes."))
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
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
        ServerBrowserDetailCard(icon: "exclamationmark.triangle", title: String(localized: "Connection Failed")) {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text(server.displayName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)

                    Text(server.subtitle)
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                }

                failureMessage

                HStack(spacing: 12) {
                    Button(action: onRetry) {
                        Label(String(localized: "Retry"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(Theme.PrimaryButtonStyle())

                    Button(action: onEdit) {
                        Label(String(localized: "Edit Server"), systemImage: "slider.horizontal.3")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.buttonRadius)
                                    .strokeBorder(Theme.cardBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 440)
        }
    }

    private var failureMessage: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(String(localized: "SSH couldn’t connect with the current settings."), systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.yellow)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(red: 0.15, green: 0.12, blue: 0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.yellow.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct ServerBrowserDetailCard<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let content: Content

    init(icon: String, title: String, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.title = title
        self.content = content()
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: icon)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(Theme.accent)

                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)

                content
            }
            .padding(32)
            .frame(maxWidth: 560)
            .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: 28))
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .strokeBorder(Theme.cardBorder, lineWidth: 1)
            )
            .padding(24)
        }
    }
}
