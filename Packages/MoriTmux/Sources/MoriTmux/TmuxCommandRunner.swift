import Foundation

/// Errors that can occur when running tmux commands.
public enum TmuxError: Error, Sendable {
    case binaryNotFound
    case executionFailed(command: String, exitCode: Int32, stderr: String)
    case notYetImplemented(String)
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
        let (output, exitCode) = try await runProcess(
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
        let (stdout, exitCode) = try await runProcess(
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
            throw TmuxError.executionFailed(command: cmd, exitCode: exitCode, stderr: stdout)
        }

        return stdout
    }

    // MARK: - Private

    private func runProcess(
        executablePath: String,
        arguments: [String]
    ) async throws -> (output: String, exitCode: Int32) {
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
                let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: (output, process.terminationStatus))
            }
        }
    }
}
