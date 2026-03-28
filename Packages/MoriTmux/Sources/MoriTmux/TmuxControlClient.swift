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
///   `CheckedContinuation` to bridge the `sendCommand` async call.
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

    // Command correlation
    private var pendingContinuation: CheckedContinuation<String, any Error>?
    private var pendingCommandNumber: Int?
    private var responseLines: [String] = []

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
    public func sendCommand(_ command: String) async throws -> String {
        guard pendingContinuation == nil else {
            throw TmuxControlError.commandInProgress
        }
        let data = Data((command + "\n").utf8)
        try await transport.write(data)
        return try await withCheckedThrowingContinuation { continuation in
            self.pendingContinuation = continuation
            self.pendingCommandNumber = nil
            self.responseLines = []
        }
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
        while let nlIndex = lineBuffer.firstIndex(of: newline) {
            let lineData = lineBuffer[lineBuffer.startIndex..<nlIndex]
            lineBuffer = Data(lineBuffer[lineBuffer.index(after: nlIndex)...])
            let lineStr = String(decoding: lineData, as: UTF8.self)
            processLine(lineStr)
        }
    }

    /// Route a parsed line to the appropriate handler.
    private func processLine(_ line: String) {
        let parsed = TmuxControlParser.parse(line)

        switch parsed {
        case .begin(_, let commandNumber, _):
            // Record the server-assigned command number
            pendingCommandNumber = commandNumber
            responseLines = []

        case .end(_, let commandNumber, _):
            guard commandNumber == pendingCommandNumber else { return }
            let result = responseLines.joined(separator: "\n")
            let cont = pendingContinuation
            pendingContinuation = nil
            pendingCommandNumber = nil
            responseLines = []
            cont?.resume(returning: result)

        case .error(_, let commandNumber, _):
            guard commandNumber == pendingCommandNumber else { return }
            let errorText = responseLines.joined(separator: "\n")
            let cont = pendingContinuation
            pendingContinuation = nil
            pendingCommandNumber = nil
            responseLines = []
            cont?.resume(throwing: TmuxControlError.commandFailed(errorText))

        case .plainLine(let text):
            // Inside a block → accumulate; outside → ignore
            if pendingCommandNumber != nil {
                responseLines.append(text)
            }

        case .output(let paneId, let data):
            paneOutputContinuation.yield((paneId: paneId, data: data))

        case .notification(let notif):
            notificationsContinuation.yield(notif)
        }
    }

    // MARK: - EOF / error

    private func handleEOF() {
        failPending(TmuxControlError.disconnected)
        paneOutputContinuation.finish()
        notificationsContinuation.finish()
    }

    private func failPending(_ error: any Error) {
        if let cont = pendingContinuation {
            pendingContinuation = nil
            pendingCommandNumber = nil
            responseLines = []
            cont.resume(throwing: error)
        }
    }
}
