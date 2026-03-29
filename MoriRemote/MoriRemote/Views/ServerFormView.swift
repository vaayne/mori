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

    @State private var name: String
    @State private var host: String
    @State private var port: String
    @State private var username: String
    @State private var password: String
    @State private var defaultSession: String

    init(mode: Mode, onSave: @escaping (Server) -> Void) {
        self.mode = mode
        self.onSave = onSave

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
    }

    private var title: String {
        switch mode {
        case .add: return "Add Server"
        case .edit: return "Edit Server"
        }
    }

    private var isValid: Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty &&
        (Int(port) ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Name (optional)
                        fieldSection("LABEL") {
                            field("My Server", text: $name)
                        }

                        // Connection
                        fieldSection("CONNECTION") {
                            field("hostname or IP", text: $host)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)

                            Divider().overlay(Theme.cardBorder)

                            HStack(spacing: 12) {
                                Text("Port")
                                    .foregroundStyle(Theme.textSecondary)
                                    .font(.subheadline)
                                Spacer()
                                TextField("22", text: $port)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }

                        // Auth
                        fieldSection("AUTHENTICATION") {
                            field("username", text: $username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                            Divider().overlay(Theme.cardBorder)

                            SecureField("password", text: $password)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .foregroundStyle(Theme.textPrimary)
                        }

                        // tmux
                        fieldSection("TMUX SESSION") {
                            field("main", text: $defaultSession)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        // Save
                        Button {
                            save()
                        } label: {
                            Text(mode.isAdd ? "Add Server" : "Save Changes")
                        }
                        .buttonStyle(Theme.PrimaryButtonStyle(disabled: !isValid))
                        .disabled(!isValid)
                        .padding(.top, 4)
                    }
                    .padding(16)
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func fieldSection(_ header: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(header)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content()
            }
            .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .strokeBorder(Theme.cardBorder, lineWidth: 1)
            )
        }
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .foregroundStyle(Theme.textPrimary)
    }

    private func save() {
        let portValue = Int(port) ?? 22
        switch mode {
        case .add:
            let server = Server(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                host: host.trimmingCharacters(in: .whitespacesAndNewlines),
                port: portValue,
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                defaultSession: defaultSession.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            onSave(server)
        case .edit(var server):
            server.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            server.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
            server.port = portValue
            server.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
            server.password = password
            server.defaultSession = defaultSession.trimmingCharacters(in: .whitespacesAndNewlines)
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
