import ArgumentParser
import Foundation

/// Connect to a relay and bridge local tmux sessions.
struct Serve: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: .localized("Connect to relay and bridge tmux sessions via WebSocket.")
    )

    @Option(name: .long, help: ArgumentHelp(.localized("Relay server URL (e.g., wss://relay.example.com/ws)")))
    var relayURL: String

    @Option(name: .long, help: ArgumentHelp(.localized("Pairing token from relay /pair endpoint")))
    var token: String

    @Option(name: .long, help: ArgumentHelp(.localized("Session ID for reconnection (overrides stored ID)")))
    var sessionID: String?

    func run() async throws {
        let connector = RelayConnector()

        // Set up signal handling for clean shutdown
        signal(SIGINT, SIG_DFL)

        // Resolve session ID: CLI flag > stored > none
        let effectiveSessionID = sessionID ?? SessionIDStore.load()
        if let effectiveSessionID {
            print("[MoriRemoteHost] Using session ID: \(effectiveSessionID)")
        }

        print("[MoriRemoteHost] Connecting to relay: \(relayURL)")

        do {
            try await connector.connect(
                relayURL: relayURL,
                token: token,
                sessionID: effectiveSessionID
            )

            // Persist session ID for reconnection across restarts
            if let newSessionID = await connector.getSessionID() {
                SessionIDStore.save(newSessionID)
            }

            // Run until cancelled or disconnected
            try await connector.runUntilDisconnected()
        } catch {
            print("[MoriRemoteHost] Error: \(error.localizedDescription)")
            throw ExitCode.failure
        }

        print("[MoriRemoteHost] Disconnected")
    }
}
