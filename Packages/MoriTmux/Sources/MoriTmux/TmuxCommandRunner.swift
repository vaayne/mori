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
/// Loads the user's login shell environment on first use so that tools installed
/// via Homebrew, mise, nix, etc. are discoverable even when launched as a .app bundle.
public actor TmuxCommandRunner {

    /// Cached path to the tmux binary, resolved on first use.
    private var resolvedBinaryPath: String?

    /// User's shell environment, loaded once on first use.
    private var shellEnvironment: [String: String]?

    public init() {}

    // MARK: - Shell Environment

    /// Load the user's login shell environment by running `env` inside their default shell.
    /// This ensures PATH includes Homebrew, mise, nix, and other user-configured paths.
    private func loadShellEnvironment() async -> [String: String] {
        if let cached = shellEnvironment {
            return cached
        }

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        do {
            let (output, _, exitCode) = try await runProcess(
                executablePath: shell,
                arguments: ["-l", "-i", "-c", "env"],
                environment: nil
            )
            if exitCode == 0 {
                var env: [String: String] = [:]
                for line in output.split(separator: "\n") {
                    if let eqIndex = line.firstIndex(of: "=") {
                        let key = String(line[line.startIndex..<eqIndex])
                        let value = String(line[line.index(after: eqIndex)...])
                        env[key] = value
                    }
                }
                shellEnvironment = env
                return env
            }
        } catch {
            // Fall through to process environment
        }

        let env = ProcessInfo.processInfo.environment
        shellEnvironment = env
        return env
    }

    // MARK: - Binary Resolution

    /// Resolve the tmux binary path. Checks common locations first,
    /// then uses the user's shell PATH via login shell env.
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

        // Load user shell env and search PATH
        let env = await loadShellEnvironment()
        if let pathVar = env["PATH"] {
            let dirs = pathVar.split(separator: ":")
            for dir in dirs {
                let candidate = "\(dir)/tmux"
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    resolvedBinaryPath = candidate
                    return candidate
                }
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
        let env = await loadShellEnvironment()
        let (stdout, stderr, exitCode) = try await runProcess(
            executablePath: binaryPath,
            arguments: arguments,
            environment: env
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
        arguments: [String],
        environment: [String: String]?
    ) async throws -> (output: String, stderr: String, exitCode: Int32) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            if let environment {
                process.environment = environment
            }
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
