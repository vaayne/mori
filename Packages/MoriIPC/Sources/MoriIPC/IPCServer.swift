import Foundation
import Network

/// Actor-based IPC server that listens on a Unix domain socket
/// and dispatches JSON-encoded requests to a handler callback.
public actor IPCServer {

    /// Handler callback type: receives a request, returns a response.
    public typealias Handler = @Sendable (IPCRequest) async -> IPCResponse

    private var listener: NWListener?
    private var connections: [Int: NWConnection] = [:]
    private var nextConnectionId = 0
    private let handler: Handler
    private let socketPath: String

    /// Default socket path in Application Support.
    public static var defaultSocketPath: String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Mori", isDirectory: true)
        return appSupport.appendingPathComponent("mori.sock").path
    }

    /// Create an IPC server.
    /// - Parameters:
    ///   - socketPath: Path for the Unix domain socket. Defaults to `~/Library/Application Support/Mori/mori.sock`.
    ///   - handler: Async callback invoked for each incoming request.
    public init(socketPath: String? = nil, handler: @escaping Handler) {
        self.socketPath = socketPath ?? Self.defaultSocketPath
        self.handler = handler
    }

    /// Start listening for connections.
    public func start() throws {
        // Ensure parent directory exists
        let parentDir = (socketPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: parentDir,
            withIntermediateDirectories: true
        )

        // Remove stale socket file
        removeSocketFile()

        // Configure NWListener for Unix domain socket
        let endpoint = NWEndpoint.unix(path: socketPath)
        let parameters = NWParameters()
        parameters.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        parameters.requiredLocalEndpoint = endpoint

        let newListener = try NWListener(using: parameters)

        newListener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let error):
                // Log and attempt restart
                print("[IPCServer] Listener failed: \(error)")
                Task { [weak self] in
                    await self?.stop()
                }
            default:
                break
            }
        }

        newListener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task {
                await self.handleNewConnection(connection)
            }
        }

        newListener.start(queue: .global(qos: .utility))
        self.listener = newListener
    }

    /// Stop the server and clean up.
    public func stop() {
        // Cancel all active connections
        for (_, connection) in connections {
            connection.cancel()
        }
        connections.removeAll()

        // Cancel the listener
        listener?.cancel()
        listener = nil

        // Remove socket file
        removeSocketFile()
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        let connectionId = nextConnectionId
        nextConnectionId += 1
        connections[connectionId] = connection

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                Task { [weak self] in
                    await self?.removeConnection(connectionId)
                }
            default:
                break
            }
        }

        connection.start(queue: .global(qos: .utility))

        // Start reading from this connection
        Task {
            await readFromConnection(connectionId: connectionId, connection: connection)
        }
    }

    private func removeConnection(_ id: Int) {
        connections.removeValue(forKey: id)
    }

    private func readFromConnection(connectionId: Int, connection: NWConnection) async {
        var buffer = Data()

        while true {
            let chunk = await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, isComplete, error in
                    if let error {
                        // Connection error
                        _ = error
                        continuation.resume(returning: nil)
                    } else if let content, !content.isEmpty {
                        continuation.resume(returning: content)
                    } else if isComplete {
                        continuation.resume(returning: nil)
                    } else {
                        // Empty read but not complete — try again
                        continuation.resume(returning: Data())
                    }
                }
            }

            guard let chunk else {
                // Connection closed or errored
                connection.cancel()
                break
            }

            buffer.append(chunk)

            // Extract complete newline-delimited messages
            let (messages, remainder) = IPCFraming.splitMessages(buffer)
            buffer = remainder

            for messageData in messages {
                await processMessage(messageData, connection: connection)
            }
        }
    }

    private func processMessage(_ data: Data, connection: NWConnection) async {
        do {
            let request = try IPCFraming.decodeRequest(from: data)
            let response = await handler(request)
            let envelope = IPCResponseEnvelope(response: response, requestId: request.requestId)
            let responseData = try IPCFraming.encode(envelope)

            connection.send(content: responseData, completion: .contentProcessed { _ in })
        } catch {
            // Malformed request — send error response
            let envelope = IPCResponseEnvelope(
                response: .error(message: "Invalid request: \(error.localizedDescription)"),
                requestId: nil
            )
            if let responseData = try? IPCFraming.encode(envelope) {
                connection.send(content: responseData, completion: .contentProcessed { _ in })
            }
        }
    }

    // MARK: - Helpers

    private nonisolated func removeSocketFile() {
        try? FileManager.default.removeItem(atPath: socketPath)
    }
}
