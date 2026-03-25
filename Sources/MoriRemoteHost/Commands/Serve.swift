import ArgumentParser
import Foundation

/// Connect to a relay and bridge local tmux sessions.
struct Serve: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Connect to relay and bridge tmux sessions via WebSocket."
    )

    @Option(name: .long, help: "Relay server URL (e.g., wss://relay.example.com/ws)")
    var relayURL: String

    @Option(name: .long, help: "Pairing token from relay /pair endpoint")
    var token: String

    @Option(name: .long, help: "Session ID for reconnection (reuse from previous connection)")
    var sessionID: String?

    func run() async throws {
        let connector = RelayConnector()

        // Install signal handlers for clean shutdown
        // Set up signal handling for clean shutdown
        signal(SIGINT, SIG_DFL)

        print("[MoriRemoteHost] Connecting to relay: \(relayURL)")

        do {
            try await connector.connect(
                relayURL: relayURL,
                token: token,
                sessionID: sessionID
            )

            // Run until cancelled or disconnected
            try await connector.runUntilDisconnected()
        } catch {
            print("[MoriRemoteHost] Error: \(error.localizedDescription)")
            throw ExitCode.failure
        }

        print("[MoriRemoteHost] Disconnected")
    }
}
