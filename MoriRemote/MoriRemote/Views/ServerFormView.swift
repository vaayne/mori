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

    private var regularWidthHorizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 24 : 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        fieldSection(String(localized: "LABEL")) {
                            field(String(localized: "My Server"), text: $name)
                        }

                        fieldSection(String(localized: "CONNECTION")) {
                            field(String(localized: "hostname or IP"), text: $host)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)

                            Divider().overlay(Theme.cardBorder)

                            HStack(spacing: 12) {
                                Text(String(localized: "Port"))
                                    .foregroundStyle(Theme.textSecondary)
                                    .font(.subheadline)
                                Spacer()
                                TextField(String(localized: "22"), text: $port)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }

                        fieldSection(String(localized: "AUTHENTICATION")) {
                            field(String(localized: "username"), text: $username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                            Divider().overlay(Theme.cardBorder)

                            SecureField(String(localized: "password"), text: $password)
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
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: formMaxWidth)
                    .padding(16)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, regularWidthHorizontalPadding)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Theme.sheetRadius)
        .presentationBackground(Theme.bg)
        .preferredColorScheme(.dark)
    }

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
