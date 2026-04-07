import SwiftUI

struct ServerListView: View {
    @Environment(ServerStore.self) private var store
    @Environment(ShellCoordinator.self) private var coordinator

    @State private var editingServer: Server?
    @State private var showingAddSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ServerListContentView(
                    servers: store.servers,
                    selectedServerID: nil,
                    connectingServerID: connectingServerID,
                    onSelect: connectToServer,
                    onAdd: { showingAddSheet = true },
                    onEdit: { editingServer = $0 },
                    onDelete: deleteServer
                )
            }
            .navigationTitle("Servers")
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
            .sheet(isPresented: $showingAddSheet) {
                ServerFormView(mode: .add) { server in
                    addServer(server)
                }
            }
            .sheet(item: $editingServer) { server in
                ServerFormView(mode: .edit(server)) { updated in
                    updateServer(updated)
                }
            }
            .overlay(alignment: .bottom) {
                if let error = coordinator.lastError {
                    ErrorBanner(message: error.localizedDescription) {
                        coordinator.lastError = nil
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var connectingServerID: Server.ID? {
        coordinator.state == .connecting ? coordinator.activeServer?.id : nil
    }

    private func connectToServer(_ server: Server) {
        guard coordinator.state == .disconnected else { return }
        Task { await coordinator.connect(server: server) }
    }

    private func addServer(_ server: Server) {
        coordinator.lastError = nil
        store.add(server)
    }

    private func updateServer(_ server: Server) {
        if coordinator.activeServer?.id == server.id {
            coordinator.lastError = nil
        }
        store.update(server)
    }

    private func deleteServer(_ server: Server) {
        if coordinator.activeServer?.id == server.id {
            coordinator.lastError = nil
        }
        store.delete(server)
    }
}

struct ServerListContentView: View {
    let servers: [Server]
    let selectedServerID: Server.ID?
    let connectingServerID: Server.ID?
    let onSelect: (Server) -> Void
    let onAdd: () -> Void
    let onEdit: (Server) -> Void
    let onDelete: (Server) -> Void

    var body: some View {
        if servers.isEmpty {
            ServerListEmptyState(onAdd: onAdd)
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(servers) { server in
                        ServerRow(
                            server: server,
                            isSelected: server.id == selectedServerID,
                            isConnecting: server.id == connectingServerID,
                            onTap: { onSelect(server) },
                            onEdit: { onEdit(server) },
                            onDelete: { onDelete(server) }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
    }
}

private struct ServerListEmptyState: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundStyle(Theme.textTertiary)

            Text("No Servers")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            Text("Add a server to get started.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)

            Button(action: onAdd) {
                Label("Add Server", systemImage: "plus")
            }
            .buttonStyle(Theme.PrimaryButtonStyle())
            .frame(maxWidth: 220)
            .padding(.top, 8)
        }
    }
}

private struct ServerRow: View {
    let server: Server
    let isSelected: Bool
    let isConnecting: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(iconBackground)
                        .frame(width: 42, height: 42)

                    if isConnecting {
                        ProgressView()
                            .tint(Theme.accent)
                    } else {
                        Image(systemName: "terminal")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(server.displayName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)

                    Text(server.subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .buttonStyle(.plain)
        .padding(16)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(rowBorder, lineWidth: 1)
        )
        .contextMenu {
            Button { onEdit() } label: {
                Label(String(localized: "Edit"), systemImage: "pencil")
            }
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label(String(localized: "Delete"), systemImage: "trash")
            }
        }
        .confirmationDialog(String(
            format: String(localized: "Delete %@?"),
            server.displayName
        ), isPresented: $showDeleteConfirm) {
            Button(String(localized: "Delete"), role: .destructive) { onDelete() }
        }
    }

    private var iconBackground: Color {
        isSelected ? Theme.accent.opacity(0.18) : Theme.accent.opacity(0.12)
    }

    private var rowBackground: Color {
        isSelected ? Theme.accent.opacity(0.12) : Theme.cardBg
    }

    private var rowBorder: Color {
        isSelected ? Theme.accent.opacity(0.35) : Theme.cardBorder
    }
}

struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(14)
        .background(Color(red: 0.15, green: 0.12, blue: 0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.yellow.opacity(0.25), lineWidth: 1)
        )
    }
}
