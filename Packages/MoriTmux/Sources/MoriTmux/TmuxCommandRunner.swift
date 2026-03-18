import Foundation

/// Errors that can occur when running tmux commands.
public enum TmuxError: Error, LocalizedError, Sendable {
    case binaryNotFound
    case executionFailed(command: String, exitCode: Int32, stderr: String)
    case notYetImplemented(String)

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "tmux binary not found. Install via: brew install tmux"
        case .executionFailed(let command, let exitCode, let stderr):
            return "tmux failed (exit \(exitCode)): \(stderr.isEmpty ? command : stderr)"
        case .notYetImplemented(let method):
            return "tmux operation not yet implemented: \(method)"
        }
    }
}

/// Runs tmux commands via `Process` (Foundation).
/// Resolves the tmux binary path via PATH lookup with common fallback locations.
public actor TmuxCommandRunner {

    /// Cached path to the tmux binary, resolved on first use.
    private var resolvedBinaryPath: String?

    public init() {}

    // MARK: - Binary Resolution

    /// Resolve the tmux binary path. Checks common locations first, then falls back to `which tmux`.
    public func resolveBinaryPath() async throws -> String {
        if let cached = resolvedBinaryPath {
            return cached
        }

        let commonPaths = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
        ]

        for path in commonPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                resolvedBinaryPath = path
                return path
            }
        }

        // Fall back to `which tmux`
        let (output, _, exitCode) = try await runProcess(
            executablePath: "/usr/bin/which",
            arguments: ["tmux"]
        )

        if exitCode == 0 {
            let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                resolvedBinaryPath = path
                return path
            }
        }

        throw TmuxError.binaryNotFound
    }

    /// Check if tmux is available on this system.
    public func isAvailable() async -> Bool {
        do {
            _ = try await resolveBinaryPath()
            return true
        } catch {
            return false
        }
    }

    // MARK: - Command Execution

    /// Run a tmux command with the given arguments. Returns stdout as a string.
    public func run(_ arguments: String...) async throws -> String {
        try await run(arguments)
    }

    /// Run a tmux command with the given arguments array. Returns stdout as a string.
    public func run(_ arguments: [String]) async throws -> String {
        let binaryPath = try await resolveBinaryPath()
        let (stdout, stderr, exitCode) = try await runProcess(
            executablePath: binaryPath,
            arguments: arguments
        )

        if exitCode != 0 {
            // tmux returns exit code 1 for some benign cases (e.g., no sessions)
            // Return empty string for those
            let cmd = "tmux \(arguments.joined(separator: " "))"
            if exitCode == 1 && stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return ""
            }
            let errorMessage = stderr.isEmpty ? stdout : stderr
            throw TmuxError.executionFailed(command: cmd, exitCode: exitCode, stderr: errorMessage)
        }

        return stdout
    }

    // MARK: - Private

    private func runProcess(
        executablePath: String,
        arguments: [String]
    ) async throws -> (output: String, stderr: String, exitCode: Int32) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            // Use terminationHandler to avoid blocking the cooperative thread pool
            process.terminationHandler = { _ in
                let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outData, encoding: .utf8) ?? ""
                let stderr = String(data: errData, encoding: .utf8) ?? ""
                continuation.resume(returning: (output, stderr, process.terminationStatus))
            }
        }
    }
}
