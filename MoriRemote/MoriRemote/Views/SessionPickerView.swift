import SwiftUI

struct SessionPickerView: View {
    @Environment(SpikeCoordinator.self) private var coordinator

    let server: Server
    let onAttach: (String) -> Void
    let onDisconnect: () -> Void

    @State private var sessions: [String] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showNewSession = false
    @State private var newSessionName: String

    init(server: Server, onAttach: @escaping (String) -> Void, onDisconnect: @escaping () -> Void) {
        self.server = server
        self.onAttach = onAttach
        self.onDisconnect = onDisconnect
        _newSessionName = State(initialValue: server.defaultSession)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                if isLoading {
                    loadingView
                } else {
                    sessionContent
                }
            }
            .navigationTitle(server.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onDisconnect()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await loadSessions() }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(Theme.accent)
                .scaleEffect(1.2)
            Text("Loading sessions…")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Content

    private var sessionContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Connected badge
                connectedBadge

                // Error
                if let loadError {
                    errorCard(loadError)
                }

                // Existing sessions
                if !sessions.isEmpty {
                    existingSessionsSection
                }

                // New session
                newSessionSection
            }
            .padding(16)
            .padding(.bottom, 16)
        }
    }

    private var connectedBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.accent)
            Text("Connected to \(server.subtitle)")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Existing Sessions

    private var existingSessionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EXISTING SESSIONS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(sessions.enumerated()), id: \.element) { index, session in
                    if index > 0 {
                        Divider().overlay(Theme.cardBorder).padding(.leading, 50)
                    }
                    sessionRow(session)
                }
            }
            .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .strokeBorder(Theme.cardBorder, lineWidth: 1)
            )
        }
    }

    private func sessionRow(_ name: String) -> some View {
        Button {
            onAttach(name)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.accent.opacity(0.12))
                        .frame(width: 36, height: 36)

                    Image(systemName: "terminal")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }

                Text(name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
    }

    // MARK: - New Session

    private var newSessionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NEW SESSION")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
                .padding(.leading, 4)

            VStack(spacing: 12) {
                TextField("session name", text: $newSessionName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .foregroundStyle(Theme.textPrimary)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))

                Button {
                    let name = newSessionName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    onAttach(name)
                } label: {
                    Label("Create & Attach", systemImage: "plus")
                }
                .buttonStyle(Theme.PrimaryButtonStyle(
                    disabled: newSessionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ))
                .disabled(newSessionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .cardStyle()
        }
    }

    // MARK: - Error

    private func errorCard(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(Theme.textTertiary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Load

    private func loadSessions() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let output = try await coordinator.runSSHCommand(
                "/opt/homebrew/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null || /usr/bin/tmux list-sessions -F '#{session_name}' 2>/dev/null || echo ''"
            )
            let names = output
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            sessions = names
            if names.isEmpty {
                loadError = "No existing tmux sessions found."
            }
        } catch {
            loadError = "Could not list sessions: \(error.localizedDescription)"
        }
    }
}
