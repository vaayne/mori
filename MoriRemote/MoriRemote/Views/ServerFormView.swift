import SwiftUI

struct ServerFormView: View {
    enum Mode: Identifiable {
        case add
        case edit(Server)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let s): return s.id.uuidString
            }
        }
    }

    let mode: Mode
    let onSave: (Server) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var name: String
    @State private var host: String
    @State private var port: String
    @State private var username: String
    @State private var password: String
    @State private var defaultSession: String
    /// Password from Mori QR — applied after a short delay and by recreating `SecureField` so iOS actually displays it.
    private let qrImportedPassword: String?
    @State private var secureFieldIdentity = UUID()

    init(mode: Mode, onSave: @escaping (Server) -> Void) {
        self.mode = mode
        self.onSave = onSave
        self.qrImportedPassword = nil

        switch mode {
        case .add:
            _name = State(initialValue: "")
            _host = State(initialValue: "")
            _port = State(initialValue: "22")
            _username = State(initialValue: "")
            _password = State(initialValue: "")
            _defaultSession = State(initialValue: "main")
        case .edit(let server):
            _name = State(initialValue: server.name)
            _host = State(initialValue: server.host)
            _port = State(initialValue: String(server.port))
            _username = State(initialValue: server.username)
            _password = State(initialValue: server.password)
            _defaultSession = State(initialValue: server.defaultSession)
        }
        _secureFieldIdentity = State(initialValue: UUID())
    }

    /// Prefill fields for a new server (e.g. QR import). On save, a new `Server` with a fresh id is created.
    init(importDraft: Server, onSave: @escaping (Server) -> Void) {
        self.mode = .add
        self.onSave = onSave
        let trimmedPassword = importDraft.password.trimmingCharacters(in: .whitespacesAndNewlines)
        self.qrImportedPassword = trimmedPassword.isEmpty ? nil : trimmedPassword
        _name = State(initialValue: importDraft.name)
        _host = State(initialValue: importDraft.host)
        _port = State(initialValue: String(importDraft.port))
        _username = State(initialValue: importDraft.username)
        _password = State(initialValue: "")
        _defaultSession = State(initialValue: importDraft.defaultSession)
        _secureFieldIdentity = State(initialValue: UUID())
    }

    private var title: String {
        switch mode {
        case .add: return String(localized: "Add Server")
        case .edit: return String(localized: "Edit Server")
        }
    }

    private var isValid: Bool {
        let p = Int(port) ?? 0
        return !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !password.isEmpty &&
            p > 0 && p <= 65535
    }

    private var formMaxWidth: CGFloat {
        horizontalSizeClass == .regular ? 560 : .infinity
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        formSummary

                        fieldSection(String(localized: "LABEL")) {
                            field(String(localized: "My Server"), text: $name)
                        }

                        fieldSection(String(localized: "CONNECTION")) {
                            field(String(localized: "hostname or IP"), text: $host)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)

                            Divider().overlay(Theme.divider)

                            HStack(spacing: 12) {
                                Text(String(localized: "Port"))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Theme.textSecondary)

                                Spacer()

                                TextField(String(localized: "22"), text: $port)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 92)
                                    .font(Theme.monoDetailFont)
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                        }

                        fieldSection(String(localized: "AUTHENTICATION")) {
                            field(String(localized: "username"), text: $username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                            Divider().overlay(Theme.divider)

                            SecureField(String(localized: "password"), text: $password)
                                .id(secureFieldIdentity)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .foregroundStyle(Theme.textPrimary)
                        }

                        fieldSection(String(localized: "TMUX SESSION")) {
                            field(String(localized: "main"), text: $defaultSession)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        Button {
                            save()
                        } label: {
                            Text(mode.isAdd ? String(localized: "Add Server") : String(localized: "Save Changes"))
                        }
                        .buttonStyle(Theme.PrimaryButtonStyle(disabled: !isValid))
                        .disabled(!isValid)
                        .padding(.top, 2)
                    }
                    .frame(maxWidth: formMaxWidth, alignment: .leading)
                    .padding(.horizontal, Theme.contentInset)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Theme.sheetRadius)
        .presentationBackground(Theme.bg)
        .preferredColorScheme(.dark)
        .task {
            guard let seed = qrImportedPassword, !seed.isEmpty else { return }
            try? await Task.sleep(nanoseconds: 120_000_000)
            password = seed
            secureFieldIdentity = UUID()
        }
    }

    private var formSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Text(mode.isAdd
                ? String(localized: "Add a server to get started.")
                : String(localized: "Review the server settings, then connect when you're ready."))
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
        }
        .cardStyle(padding: 18)
    }

    @ViewBuilder
    private func fieldSection(_ header: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(header)
                .moriSectionHeaderStyle()
                .padding(.leading, 2)

            VStack(spacing: 0) {
                content()
            }
            .cardStyle(padding: 0)
        }
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 14))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .foregroundStyle(Theme.textPrimary)
    }

    private func save() {
        let portValue = Int(port) ?? 22
        let normalizedDefaultSession = {
            let trimmed = defaultSession.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "main" : trimmed
        }()

        switch mode {
        case .add:
            let server = Server(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                host: host.trimmingCharacters(in: .whitespacesAndNewlines),
                port: portValue,
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                defaultSession: normalizedDefaultSession
            )
            onSave(server)
        case .edit(var server):
            server.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            server.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
            server.port = portValue
            server.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
            server.password = password
            server.defaultSession = normalizedDefaultSession
            onSave(server)
        }
        dismiss()
    }
}

extension ServerFormView.Mode {
    var isAdd: Bool {
        if case .add = self { return true }
        return false
    }
}
