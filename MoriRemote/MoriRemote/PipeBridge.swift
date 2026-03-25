import Foundation

/// Bidirectional bridge between ghostty's Remote backend pipe fd pair and a data source/sink.
///
/// The bridge manages two pipes:
/// - `pipeToGhostty`: External data (future WebSocket) is written here; ghostty reads from `readFD`
/// - `pipeFromGhostty`: ghostty writes user input here; the bridge reads from `readFD` and forwards out
///
/// ```
///                          iOS App
/// ┌─────────────┐    pipeToGhostty      ┌──────────────┐
/// │ PipeBridge  │ ───write──> [readFD] ──>│ ghostty      │
/// │ (data       │                         │ Remote       │
/// │  source)    │ <──read─── [writeFD] <──│ backend      │
/// └─────────────┘    pipeFromGhostty      └──────────────┘
/// ```
actor PipeBridge {

    // MARK: - Pipe FDs exposed to ghostty surface config

    /// FD that ghostty reads terminal output from (we write to the other end).
    let ghosttyReadFD: Int32

    /// FD that ghostty writes user input to (we read from the other end).
    let ghosttyWriteFD: Int32

    // MARK: - Internal pipe ends

    /// Write end of pipeToGhostty — we write terminal output bytes here.
    private let writeToGhostty: Int32

    /// Read end of pipeFromGhostty — we read user input bytes from here.
    private let readFromGhostty: Int32

    // MARK: - State

    private var isRunning = false
    private var readSource: DispatchSourceRead?

    /// Callback invoked on the bridge actor when ghostty writes user input.
    /// Set via `setOnInputFromGhostty(_:)` to forward data to WebSocket.
    private(set) var onInputFromGhostty: (@Sendable (Data) async throws -> Void)?

    /// Set the callback for user input from ghostty (e.g., to forward to WebSocket).
    func setOnInputFromGhostty(_ callback: (@Sendable (Data) async throws -> Void)?) {
        self.onInputFromGhostty = callback
    }

    // MARK: - Init

    init() throws {
        // Pipe for terminal output -> ghostty (we write, ghostty reads)
        var toGhostty: [Int32] = [0, 0]
        guard pipe(&toGhostty) == 0 else {
            throw PipeBridgeError.pipeCreationFailed(errno: errno)
        }

        // Pipe for ghostty input -> us (ghostty writes, we read)
        var fromGhostty: [Int32] = [0, 0]
        guard pipe(&fromGhostty) == 0 else {
            // Clean up first pipe
            close(toGhostty[0])
            close(toGhostty[1])
            throw PipeBridgeError.pipeCreationFailed(errno: errno)
        }

        // pipeToGhostty: [0]=read (ghostty), [1]=write (us)
        self.ghosttyReadFD = toGhostty[0]
        self.writeToGhostty = toGhostty[1]

        // pipeFromGhostty: [0]=read (us), [1]=write (ghostty)
        self.readFromGhostty = fromGhostty[0]
        self.ghosttyWriteFD = fromGhostty[1]

        // Set non-blocking on our read end so we can use async I/O
        let flags = fcntl(self.readFromGhostty, F_GETFL)
        if flags >= 0 {
            _ = fcntl(self.readFromGhostty, F_SETFL, flags | O_NONBLOCK)
        }
    }

    deinit {
        // Close all pipe file descriptors
        close(ghosttyReadFD)
        close(writeToGhostty)
        close(readFromGhostty)
        close(ghosttyWriteFD)
    }

    // MARK: - Lifecycle

    /// Start the read loop that monitors ghostty's output (user input from the terminal).
    /// Uses a DispatchSource to efficiently wait for data instead of polling.
    func start() {
        guard !isRunning else { return }
        isRunning = true

        let readFD = self.readFromGhostty
        let source = DispatchSource.makeReadSource(fileDescriptor: readFD, queue: .global(qos: .userInteractive))
        self.readSource = source

        source.setEventHandler { [weak self] in
            let bufferSize = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }

            let bytesRead = read(readFD, buffer, bufferSize)
            if bytesRead > 0 {
                let data = Data(bytes: buffer, count: bytesRead)
                if let self {
                    Task {
                        let callback = await self.onInputFromGhostty
                        try? await callback?(data)
                    }
                }
            } else if bytesRead == 0 {
                // EOF — pipe closed
                source.cancel()
            }
            // EAGAIN is fine — DispatchSource will re-fire when data arrives
        }

        source.setCancelHandler { [weak self] in
            Task { await self?.stop() }
        }

        source.resume()
    }

    /// Stop the read loop and clean up.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        if let source = readSource {
            source.cancel()
            readSource = nil
        }
    }

    // MARK: - Writing terminal output to ghostty

    /// Write terminal output data to ghostty's read pipe.
    /// Called when data arrives from the network (future WebSocket) or test harness.
    func writeToTerminal(_ data: Data) {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var totalWritten = 0
            let count = rawBuffer.count
            while totalWritten < count {
                let written = write(
                    writeToGhostty,
                    baseAddress.advanced(by: totalWritten),
                    count - totalWritten
                )
                if written > 0 {
                    totalWritten += written
                } else if written < 0 {
                    if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR {
                        continue
                    }
                    // Real error — pipe broken
                    break
                }
            }
        }
    }
}

// MARK: - Errors

enum PipeBridgeError: Error, CustomStringConvertible {
    case pipeCreationFailed(errno: Int32)

    var description: String {
        switch self {
        case .pipeCreationFailed(let errno):
            "Failed to create pipe: \(String(cString: strerror(errno)))"
        }
    }
}
