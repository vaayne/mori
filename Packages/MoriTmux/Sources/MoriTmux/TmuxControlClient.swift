import Foundation

/// Error type for control-mode client failures.
public enum TmuxControlError: Error, Sendable, LocalizedError {
    /// The tmux server returned `%error` for a command.
    case commandFailed(String)
    /// The transport closed while a command was in-flight.
    case disconnected
    /// A command was already in-flight (spike: one at a time).
    case commandInProgress

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let msg): return "tmux command failed: \(msg)"
        case .disconnected: return "tmux control-mode disconnected"
        case .commandInProgress: return "another tmux command is already in progress"
        }
    }
}

/// Actor that drives a tmux control-mode session over a `TmuxTransport`.
///
/// Responsibilities:
/// - **Line buffering**: incoming `Data` chunks are accumulated; complete
///   `\n`-terminated lines are extracted and fed to `TmuxControlParser`.
/// - **Block tracking**: tracks `%begin/%end` state. `.plainLine` results
///   inside a block are accumulated as command response text.
/// - **Command serialization**: one command at a time for the spike. Uses
///   an `AsyncStream` to bridge the `sendCommand` async call, avoiding
///   actor reentrancy races with `CheckedContinuation`.
/// - **Routing**: `%output` → `paneOutput` stream, notifications → `notifications` stream.
public actor TmuxControlClient {

    // MARK: - Public streams

    /// Stream of decoded pane output from `%output` lines.
    public let paneOutput: AsyncStream<(paneId: String, data: Data)>

    /// Stream of async notifications from the tmux server.
    public let notifications: AsyncStream<TmuxNotification>

    // MARK: - Private state

    private let transport: any TmuxTransport
    private var readTask: Task<Void, Never>?
    private var lineBuffer = Data()

    // Stream continuations
    private let paneOutputContinuation: AsyncStream<(paneId: String, data: Data)>.Continuation
    private let notificationsContinuation: AsyncStream<TmuxNotification>.Continuation

    // Command correlation — uses AsyncStream instead of CheckedContinuation
    // to avoid actor reentrancy races between the read task and sendCommand.
    private var awaitingResponse = false
    private var responseContinuation: AsyncStream<Result<String, any Error>>.Continuation?
    private var pendingCommandNumber: Int?
    private var responseLines: [String] = []
    private var ready = false  // Set after handshake is drained

    // MARK: - Init

    public init(transport: any TmuxTransport) {
        self.transport = transport
        let (paneStream, paneCont) = AsyncStream<(paneId: String, data: Data)>.makeStream()
        self.paneOutput = paneStream
        self.paneOutputContinuation = paneCont
        let (notifStream, notifCont) = AsyncStream<TmuxNotification>.makeStream()
        self.notifications = notifStream
        self.notificationsContinuation = notifCont
    }

    // MARK: - Lifecycle

    /// Start reading from the transport. Call once after init.
    public func start() {
        guard readTask == nil else { return }
        readTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await chunk in self.transport.inbound {
                    await self.receive(chunk)
                }
            } catch {
                // Transport error — treat as EOF
            }
            await self.handleEOF()
        }
    }

    /// Mark the client as ready to accept commands.
    /// Call after the initial handshake has been drained.
    public func markReady() {
        ready = true
    }

    /// Wait for the initial tmux handshake to complete, then mark ready.
    /// Call after `start()` and before sending any commands.
    public func waitForReady() async {
        try? await Task.sleep(for: .milliseconds(500))
        markReady()
    }

    /// Stop the client, close the transport, and cancel any in-flight command.
    public func stop() async {
        readTask?.cancel()
        readTask = nil
        failPending(TmuxControlError.disconnected)
        paneOutputContinuation.finish()
        notificationsContinuation.finish()
        await transport.close()
    }

    // MARK: - Send command

    /// Send a command to the tmux server and await its response.
    ///
    /// The command is written newline-terminated. The client waits for a
    /// `%begin` response, accumulates `.plainLine` responses, and resolves
    /// on `%end` (success) or `%error` (failure).
    ///
    /// Uses an `AsyncStream` instead of `CheckedContinuation` to avoid
    /// actor reentrancy: the response state (`awaitingResponse`,
    /// `responseContinuation`) is set synchronously before the write
    /// suspends, so the read task can deliver the response at any point.
    public func sendCommand(_ command: String) async throws -> String {
        guard !awaitingResponse else {
            throw TmuxControlError.commandInProgress
        }

        // Set up response channel BEFORE writing so fast responses are caught.
        let (stream, continuation) = AsyncStream<Result<String, any Error>>.makeStream()
        awaitingResponse = true
        responseContinuation = continuation
        pendingCommandNumber = nil
        responseLines = []

        // Write the command — the actor suspends here, allowing the read
        // task to process incoming data and deliver the response.
        let data = Data((command + "\n").utf8)
        try? await transport.write(data)

        // Await the response from the stream.
        guard let result = await stream.first(where: { _ in true }) else {
            awaitingResponse = false
            responseContinuation = nil
            throw TmuxControlError.disconnected
        }

        awaitingResponse = false
        responseContinuation = nil
        return try result.get()
    }

    // MARK: - Receive pipeline

    /// Append incoming data to the line buffer and process complete lines.
    private func receive(_ chunk: Data) {
        lineBuffer.append(chunk)
        extractAndProcessLines()
    }

    /// Extract complete `\n`-terminated lines from the buffer.
    private func extractAndProcessLines() {
        let newline = UInt8(ascii: "\n")
        let cr = UInt8(ascii: "\r")
        while let nlIndex = lineBuffer.firstIndex(of: newline) {
            var lineData = lineBuffer[lineBuffer.startIndex..<nlIndex]
            lineBuffer = Data(lineBuffer[lineBuffer.index(after: nlIndex)...])
            // Strip trailing \r (SSH channels often send \r\n)
            if let last = lineData.last, last == cr {
                lineData = lineData.dropLast()
            }
            let lineStr = String(decoding: lineData, as: UTF8.self)
            processLine(lineStr)
        }
    }

    /// Route a parsed line to the appropriate handler.
    private func processLine(_ line: String) {
        let parsed = TmuxControlParser.parse(line)

        switch parsed {
        case .begin(_, let commandNumber, _):
            // Only track begin/end after handshake is drained (ready=true)
            // AND when a command is awaiting a response.
            guard ready, awaitingResponse else { return }
            pendingCommandNumber = commandNumber
            responseLines = []

        case .end(_, let commandNumber, _):
            guard commandNumber == pendingCommandNumber else { return }
            let result = responseLines.joined(separator: "\n")
            pendingCommandNumber = nil
            responseLines = []
            responseContinuation?.yield(.success(result))
            responseContinuation?.finish()

        case .error(_, let commandNumber, _):
            guard commandNumber == pendingCommandNumber else { return }
            let errorText = responseLines.joined(separator: "\n")
            pendingCommandNumber = nil
            responseLines = []
            responseContinuation?.yield(.failure(TmuxControlError.commandFailed(errorText)))
            responseContinuation?.finish()

        case .plainLine(let text):
            // Inside a block → accumulate; outside → ignore
            if pendingCommandNumber != nil {
                responseLines.append(text)
            }

        case .output(let paneId, let data):
            paneOutputContinuation.yield((paneId: paneId, data: data))

        case .notification(let notif):
            // Inside a command block, unknown lines starting with %
            // (like pane IDs "%0", "%1") are parsed as .notification(.unknown).
            // Treat them as response lines instead.
            if pendingCommandNumber != nil, case .unknown(let raw) = notif {
                responseLines.append(raw)
            } else {
                notificationsContinuation.yield(notif)
            }
        }
    }

    // MARK: - EOF / error

    private func handleEOF() {
        failPending(TmuxControlError.disconnected)
        paneOutputContinuation.finish()
        notificationsContinuation.finish()
    }

    private func failPending(_ error: any Error) {
        if awaitingResponse {
            awaitingResponse = false
            pendingCommandNumber = nil
            responseLines = []
            responseContinuation?.yield(.failure(error))
            responseContinuation?.finish()
            responseContinuation = nil
        }
    }
}
