import SwiftUI

struct ConnectView: View {
    @Environment(SpikeCoordinator.self) private var coordinator

    @State private var host = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Host", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)

                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("Password", text: $password)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Connect") {
                        connect()
                    }
                    .disabled(isConnectDisabled)
                }
            }
            .navigationTitle("Mori Remote")
            .overlay {
                if coordinator.state.isConnecting {
                    ProgressView("Connecting...")
                        .padding(20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    private var errorMessage: String? {
        guard case .disconnected(let error) = coordinator.state, let error else {
            return nil
        }
        return error.localizedDescription
    }

    private var isConnectDisabled: Bool {
        coordinator.state.isConnecting ||
            host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            password.isEmpty
    }

    private func connect() {
        guard let portValue = Int(port), portValue > 0 else {
            coordinator.presentDisconnected(error: SpikeCoordinatorError.invalidPort)
            return
        }

        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            await coordinator.connect(
                host: trimmedHost,
                port: portValue,
                user: trimmedUser,
                password: password
            )
        }
    }
}

#Preview {
    ConnectView()
        .environment(SpikeCoordinator())
}
