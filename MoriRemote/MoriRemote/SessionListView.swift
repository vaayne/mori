import SwiftUI
import MoriRemoteProtocol

/// Displays available tmux sessions from the relay host.
/// Tap a session to attach and open the terminal view.
struct SessionListView: View {
    let sessions: [SessionInfo]
    let connectionStatus: ConnectionStatus
    let onAttach: (SessionInfo) -> Void
    let onRefresh: () -> Void
    let onForgetDevice: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if sessions.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            onRefresh()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        Divider()
                        Button(role: .destructive) {
                            onForgetDevice()
                        } label: {
                            Label("Forget This Device", systemImage: "xmark.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    // MARK: - Session List

    private var sessionList: some View {
        List {
            Section {
                ForEach(sessions) { session in
                    SessionRow(session: session) {
                        onAttach(session)
                    }
                }
            } header: {
                Text("\(sessions.count) session\(sessions.count == 1 ? "" : "s")")
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            onRefresh()
            // Brief delay so the refresh indicator is visible
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Sessions")
                .font(.title3.bold())
                .foregroundStyle(.primary)
            Text("No tmux sessions found on the host.\nCreate a session on your Mac first.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                onRefresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
        }
        .padding()
    }
}

// MARK: - Session Row

private struct SessionRow: View {
    let session: SessionInfo
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Status indicator
                Circle()
                    .fill(session.attached ? .green : .gray.opacity(0.5))
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.displayName)
                        .font(.body.bold())
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        if session.displayName != session.name {
                            Text(session.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("\(session.windowCount) window\(session.windowCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if session.attached {
                    Text("active")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.15))
                        .clipShape(Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
