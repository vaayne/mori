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
                    .padding(.horizontal, Theme.contentInset)
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
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    Text(String(localized: "Servers"))
                        .moriSectionHeaderStyle()
                        .padding(.horizontal, Theme.contentInset)

                    LazyVStack(spacing: Theme.rowSpacing) {
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
                    .padding(.horizontal, Theme.contentInset)
                }
                .padding(.top, 12)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct ServerListEmptyState: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 40)

            Image(systemName: "server.rack")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)

            Text(String(localized: "No Servers"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Text(String(localized: "Add a server to get started."))
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            Button(action: onAdd) {
                Label(String(localized: "Add Server"), systemImage: "plus")
            }
            .buttonStyle(Theme.PrimaryButtonStyle())
            .frame(maxWidth: 220)
            .padding(.top, 4)

            Spacer()
        }
        .padding(.horizontal, 24)
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
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.rowRadius)
                        .fill(isSelected ? Theme.accentSoft : Theme.mutedSurface)
                        .frame(width: 36, height: 36)

                    if isConnecting {
                        ProgressView()
                            .tint(Theme.accent)
                            .scaleEffect(0.9)
                    } else {
                        Image(systemName: "terminal")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(server.displayName)
                        .font(Theme.rowTitleFont)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)

                    Text(server.subtitle)
                        .font(Theme.monoCaptionFont)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isConnecting {
                    Text(String(localized: "Connecting…"))
                        .font(Theme.shortcutFont)
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 5))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .rowSurfaceStyle(selected: isSelected)
        }
        .buttonStyle(.plain)
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
}

struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warning)

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(12)
        .background(Color(red: 0.18, green: 0.14, blue: 0.08), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.warning.opacity(0.24), lineWidth: 1)
        )
    }
}
