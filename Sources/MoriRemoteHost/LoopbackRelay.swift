import Foundation
import MoriRemoteProtocol
import Network

/// A minimal in-process WebSocket relay for local testing.
/// Uses Network.framework NWListener with WebSocket protocol to accept
/// host and viewer connections and relay bytes bidirectionally.
/// Eliminates the need for the Go relay during development and testing.
actor LoopbackRelay {

    private var listener: NWListener?
    private let port: UInt16
    private var hostConnection: NWConnection?
    private var viewerConnection: NWConnection?

    /// Whether the relay is running.
    private(set) var isRunning = false

    /// The WebSocket URL clients should connect to.
    var url: String { "ws://127.0.0.1:\(port)/ws" }

    /// Token for pairing (static for loopback).
    let pairingToken = "loopback-test-token"

    init(port: UInt16 = 9876) {
        self.port = port
    }

    /// Start the loopback relay server.
    func start() throws {
        let parameters = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        self.listener = listener

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[LoopbackRelay] Listening on port \(self.port)")
            case .failed(let error):
                print("[LoopbackRelay] Listener failed: \(error)")
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task {
                await self.handleNewConnection(connection)
            }
        }

        listener.start(queue: .global(qos: .utility))
        isRunning = true
        print("[LoopbackRelay] Started on port \(port)")
    }

    /// Stop the relay.
    func stop() {
        listener?.cancel()
        listener = nil
        hostConnection?.cancel()
        hostConnection = nil
        viewerConnection?.cancel()
        viewerConnection = nil
        isRunning = false
        print("[LoopbackRelay] Stopped")
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))

        // Determine role from the first message (handshake)
        receiveMessage(on: connection) { [weak self] data, context, isComplete in
            guard let self, let data else { return }

            // Try to parse as control message to determine role
            if let message = try? decodeMessage(data) {
                switch message {
                case .handshake(let hs):
                    Task {
                        await self.registerConnection(connection, role: hs.role)
                        // Echo back a handshake with session ID
                        let response = ControlMessage.handshake(
                            ControlMessage.Handshake(
                                role: hs.role,
                                capabilities: ["session_id:loopback-session-\(UUID().uuidString.prefix(8))"]
                            )
                        )
                        if let responseData = try? encodeMessage(response),
                           let text = String(data: responseData, encoding: .utf8) {
                            let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
                            let wsContext = NWConnection.ContentContext(
                                identifier: "text",
                                metadata: [metadata]
                            )
                            connection.send(
                                content: text.data(using: .utf8),
                                contentContext: wsContext,
                                completion: .contentProcessed { _ in }
                            )
                        }
                        // Start relaying
                        await self.startRelaying(connection: connection, role: hs.role)
                    }
                default:
                    break
                }
            }
        }
    }

    private func registerConnection(_ connection: NWConnection, role: Role) {
        switch role {
        case .host:
            hostConnection = connection
            print("[LoopbackRelay] Host connected")
        case .viewer:
            viewerConnection = connection
            print("[LoopbackRelay] Viewer connected")
        }
    }

    private func startRelaying(connection: NWConnection, role: Role) async {
        relayReadLoop(connection: connection, role: role)
    }

    /// Recursive read loop extracted as a nonisolated method to satisfy Sendable.
    private nonisolated func relayReadLoop(connection: NWConnection, role: Role) {
        receiveMessage(on: connection) { [weak self] data, context, isComplete in
            guard let self, let data else { return }

            Task {
                let target: NWConnection?
                switch role {
                case .host: target = await self.viewerConnection
                case .viewer: target = await self.hostConnection
                }

                if let target {
                    let metadata: NWProtocolWebSocket.Metadata
                    if let wsMetadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata {
                        metadata = NWProtocolWebSocket.Metadata(opcode: wsMetadata.opcode)
                    } else {
                        metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
                    }

                    let wsContext = NWConnection.ContentContext(
                        identifier: "relay",
                        metadata: [metadata]
                    )
                    target.send(
                        content: data,
                        contentContext: wsContext,
                        completion: .contentProcessed { _ in }
                    )
                }

                // Continue reading
                self.relayReadLoop(connection: connection, role: role)
            }
        }
    }

    private nonisolated func receiveMessage(
        on connection: NWConnection,
        handler: @escaping @Sendable (Data?, NWConnection.ContentContext?, Bool) -> Void
    ) {
        connection.receiveMessage { content, context, isComplete, error in
            handler(content, context, isComplete)
        }
    }
}

// MARK: - Loopback Test Harness

/// Runs a simple end-to-end loopback test:
/// 1. Starts a LoopbackRelay
/// 2. Connects a RelayConnector as host
/// 3. Verifies the connection succeeds and session listing works
enum LoopbackHarness {

    static func run(port: UInt16 = 9876) async throws {
        print("=== Loopback Harness ===")
        print()

        // 1. Start the loopback relay
        let relay = LoopbackRelay(port: port)
        try await relay.start()

        // Give the listener a moment to start
        try await Task.sleep(for: .seconds(0.5))

        // 2. Connect a RelayConnector as host
        let connector = RelayConnector()
        let relayURL = await relay.url

        print("[Harness] Connecting connector to \(relayURL)...")

        do {
            try await connector.connect(
                relayURL: relayURL,
                token: relay.pairingToken
            )
            print("[Harness] Connector connected successfully")
        } catch {
            print("[Harness] Connection failed: \(error)")
            await relay.stop()
            throw error
        }

        // 3. Verify session listing
        print("[Harness] Listing local tmux sessions...")
        let lister = SessionLister()
        do {
            let sessions = try await lister.listSessions()
            print("[Harness] Found \(sessions.count) sessions:")
            for session in sessions {
                print("  - \(session.displayName) [\(session.name)] (\(session.windowCount) windows)")
            }
        } catch {
            print("[Harness] Session listing failed (tmux may not be running): \(error)")
        }

        // 4. Verify session ID was received
        if let sid = await connector.getSessionID() {
            print("[Harness] Session ID received: \(sid)")
        } else {
            print("[Harness] No session ID received (expected for loopback)")
        }

        // 5. Check connector state
        let state = await connector.currentState()
        print("[Harness] Connector state: \(state)")

        // Cleanup
        await relay.stop()

        print()
        print("=== Loopback Harness Complete ===")
    }
}
