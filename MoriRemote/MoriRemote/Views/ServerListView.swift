import SwiftUI

struct ServerListView: View {
    @Environment(ServerStore.self) private var store
    @Environment(SpikeCoordinator.self) private var coordinator

    @State private var editingServer: Server?
    @State private var showingAddSheet = false
    @State private var connectingServerId: UUID?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                if store.servers.isEmpty {
                    emptyState
                } else {
                    serverList
                }
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
                    store.add(server)
                }
            }
            .sheet(item: $editingServer) { server in
                ServerFormView(mode: .edit(server)) { updated in
                    store.update(updated)
                }
            }
            .overlay(alignment: .bottom) {
                if let errorMessage {
                    ErrorBanner(message: errorMessage) {
                        withAnimation { self.errorMessage = nil }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: coordinator.stateKey) { _, newKey in
            if newKey == "disconnected", case .disconnected(let error) = coordinator.state, let error {
                withAnimation {
                    errorMessage = error.localizedDescription
                    connectingServerId = nil
                }
            }
            if newKey == "connected" {
                connectingServerId = nil
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
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

            Button {
                showingAddSheet = true
            } label: {
                Label("Add Server", systemImage: "plus")
            }
            .buttonStyle(Theme.PrimaryButtonStyle())
            .frame(maxWidth: 220)
            .padding(.top, 8)
        }
    }

    // MARK: - Server List

    private var serverList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(store.servers) { server in
                    ServerRow(
                        server: server,
                        isConnecting: connectingServerId == server.id,
                        onTap: { connectToServer(server) },
                        onEdit: { editingServer = server },
                        onDelete: { store.delete(server) }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Connect

    private func connectToServer(_ server: Server) {
        guard connectingServerId == nil else { return }
        withAnimation { errorMessage = nil }

        connectingServerId = server.id
        NotificationCenter.default.post(name: .serverSelected, object: ServerBox(server))

        Task {
            await coordinator.connect(
                host: server.host.trimmingCharacters(in: .whitespacesAndNewlines),
                port: server.port,
                user: server.username.trimmingCharacters(in: .whitespacesAndNewlines),
                password: server.password
            )
        }
    }
}

// MARK: - Server Row

private struct ServerRow: View {
    let server: Server
    let isConnecting: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.accent.opacity(0.12))
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

                // Text
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

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .cardStyle()
        .contextMenu {
            Button { onEdit() } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .confirmationDialog("Delete \(server.displayName)?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { onDelete() }
        }
    }
}

// MARK: - Error Banner

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
