import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Bridges a child process running in a pseudo-terminal (pty).
/// Uses `forkpty()` to create a pty pair and run a command (typically `tmux attach`).
/// Provides read/write access to the pty master for bidirectional I/O.
final class PTYBridge: @unchecked Sendable {

    /// File descriptor for the master side of the pty.
    private let masterFD: Int32

    /// PID of the child process.
    private let childPID: pid_t

    /// Whether the child process is still alive.
    private(set) var isAlive: Bool = true

    /// Lock for thread-safe state access.
    private let lock = NSLock()

    /// Create a PTYBridge by forking a child process with the given command.
    /// - Parameter command: Array of command arguments, e.g. `["tmux", "attach-session", "-t", "mori/main"]`.
    init(command: [String]) throws {
        guard !command.isEmpty else {
            throw PTYBridgeError.emptyCommand
        }

        var masterFD: Int32 = -1
        var winSize = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)

        let pid = forkpty(&masterFD, nil, nil, &winSize)

        if pid < 0 {
            throw PTYBridgeError.forkFailed(errno: errno)
        }

        if pid == 0 {
            // Child process — exec the command
            // Note: no defer needed here. On success, execvp replaces the process image
            // (defer never runs). On failure, _exit(127) terminates immediately.
            let cArgs = command.map { strdup($0) } + [nil]
            execvp(command[0], cArgs)
            // If execvp returns, it failed
            _exit(127)
        }

        // Parent process
        self.masterFD = masterFD
        self.childPID = pid

        // Make the master fd non-blocking for reads
        let flags = fcntl(masterFD, F_GETFL)
        if flags >= 0 {
            // Keep blocking for now — we use a dedicated read thread
        }

        // Monitor child exit in background
        monitorChildExit()
    }

    deinit {
        terminate()
    }

    // MARK: - I/O

    /// Read from the pty master. Returns the number of bytes read, 0 for EOF, -1 for error.
    func read(into buffer: inout [UInt8], maxLength: Int) -> Int {
        lock.lock()
        let alive = isAlive
        let fd = masterFD
        lock.unlock()

        guard alive, fd >= 0 else { return 0 }

        let result = buffer.withUnsafeMutableBufferPointer { ptr in
            Darwin.read(fd, ptr.baseAddress!, min(maxLength, ptr.count))
        }

        return result
    }

    /// Write data to the pty master (sends input to the child process).
    func write(_ data: Data) {
        lock.lock()
        let alive = isAlive
        let fd = masterFD
        lock.unlock()

        guard alive, fd >= 0 else { return }

        data.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            var written = 0
            while written < data.count {
                let result = Darwin.write(fd, base.advanced(by: written), data.count - written)
                if result <= 0 {
                    if errno == EINTR { continue }
                    break
                }
                written += result
            }
        }
    }

    /// Resize the pty window.
    func resize(cols: UInt16, rows: UInt16) {
        lock.lock()
        let fd = masterFD
        lock.unlock()

        guard fd >= 0 else { return }

        var ws = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(fd, TIOCSWINSZ, &ws)
    }

    /// Terminate the child process and close the pty.
    ///
    /// Sends SIGHUP to request graceful exit, then closes the master fd.
    /// The background `monitorChildExit()` thread handles reaping via `waitpid`.
    /// If the child doesn't exit promptly, `monitorChildExit` will still collect it.
    func terminate() {
        lock.lock()
        guard isAlive else {
            lock.unlock()
            return
        }
        isAlive = false
        let fd = masterFD
        let pid = childPID
        lock.unlock()

        // Send SIGHUP to request graceful exit
        kill(pid, SIGHUP)

        // Close the master fd — this unblocks any pending reads and
        // signals EOF to the child's pty slave side.
        if fd >= 0 {
            close(fd)
        }

        // Schedule a forced kill in case SIGHUP wasn't enough.
        // monitorChildExit() handles the actual waitpid reaping.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            kill(pid, SIGKILL)
        }
    }

    // MARK: - Private

    private func monitorChildExit() {
        let pid = childPID
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var status: Int32 = 0
            waitpid(pid, &status, 0)

            guard let self else { return }
            self.lock.lock()
            self.isAlive = false
            self.lock.unlock()
        }
    }
}

// MARK: - Errors

enum PTYBridgeError: Error, LocalizedError {
    case emptyCommand
    case forkFailed(errno: Int32)

    var errorDescription: String? {
        switch self {
        case .emptyCommand: "Cannot create PTY bridge with empty command"
        case .forkFailed(let errno): "forkpty() failed with errno \(errno)"
        }
    }
}
