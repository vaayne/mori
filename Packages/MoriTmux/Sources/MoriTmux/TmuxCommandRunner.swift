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

/// Thread-safe, Sendable wrapper around CheckedContinuation to ensure single resume.
private final class SendableResumeGuard<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false
    private let continuation: CheckedContinuation<T, any Error>

    init(continuation: CheckedContinuation<T, any Error>) {
        self.continuation = continuation
    }

    func resume(with result: sending Result<T, any Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        continuation.resume(with: result)
    }
}

/// Runs tmux commands via `Process` (Foundation).
/// Resolves the tmux binary path via PATH lookup with common fallback locations.
/// Loads the user's login shell environment on first use so that tools installed
/// via Homebrew, mise, nix, etc. are discoverable even when launched as a .app bundle.
public actor TmuxCommandRunner {
    private static let commonBinaryPaths = [
        "/opt/homebrew/bin/tmux",
        "/usr/local/bin/tmux",
    ]

    /// Cached path to the tmux binary, resolved on first use.
    private var resolvedBinaryPath: String?

    /// User's shell environment, loaded once on first use.
    private var shellEnvironment: [String: String]?

    public init() {}

    // MARK: - Shell Environment

    /// Load the user's shell environment for running tmux commands.
    /// First tries the inherited process environment (fast — works when launched from terminal).
    /// Falls back to spawning a login shell to discover PATH (for .app bundle launches).
    private func loadShellEnvironment() async -> [String: String] {
        if let cached = shellEnvironment {
            return cached
        }

        // Try the inherited process environment first — this is instant and works
        // when launched from a terminal that already has the full PATH.
        let processEnv = ProcessInfo.processInfo.environment
        if hasTmuxOnPath(processEnv) {
            shellEnvironment = processEnv
            return processEnv
        }

        // Fallback: spawn a login shell to discover the full PATH.
        // Needed when launched as a .app bundle with a minimal environment.
        let shell = processEnv["SHELL"] ?? "/bin/zsh"
        do {
            let (output, _, exitCode) = try await runProcess(
                executablePath: shell,
                arguments: ["-l", "-i", "-c", "env"],
                environment: processEnv,
                stdinNull: true,
                timeoutSeconds: 10
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

        shellEnvironment = processEnv
        return processEnv
    }

    /// Quick check: is tmux findable on PATH in the given environment?
    private func hasTmuxOnPath(_ env: [String: String]) -> Bool {
        for path in Self.commonBinaryPaths {
            if FileManager.default.isExecutableFile(atPath: path) { return true }
        }
        guard let pathVar = env["PATH"] else { return false }
        return pathVar.split(separator: ":").contains { dir in
            FileManager.default.isExecutableFile(atPath: "\(dir)/tmux")
        }
    }

    /// Best-effort synchronous lookup for UI launch commands before async resolution completes.
    public static func preferredBinaryPath(in environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        for path in commonBinaryPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        guard let pathVar = environment["PATH"] else { return nil }
        for dir in pathVar.split(separator: ":") {
            let candidate = "\(dir)/tmux"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    // MARK: - Binary Resolution

    /// Resolve the tmux binary path. Checks common locations first,
    /// then uses the user's shell PATH via login shell env.
    public func resolveBinaryPath() async throws -> String {
        if let cached = resolvedBinaryPath {
            return cached
        }

        for path in Self.commonBinaryPaths {
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
        environment: [String: String]?,
        stdinNull: Bool = false,
        timeoutSeconds: Int? = nil
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
            if stdinNull {
                process.standardInput = FileHandle.nullDevice
            }

            let guard_ = SendableResumeGuard(continuation: continuation)

            do {
                try process.run()
            } catch {
                guard_.resume(with: .failure(error))
                return
            }

            // Use terminationHandler to avoid blocking the cooperative thread pool
            process.terminationHandler = { _ in
                let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outData, encoding: .utf8) ?? ""
                let stderr = String(data: errData, encoding: .utf8) ?? ""
                guard_.resume(with: .success((output, stderr, process.terminationStatus)))
            }

            // Kill the process if it exceeds the timeout.
            // The SendableResumeGuard prevents double-resume if both timeout and
            // normal termination fire. Process stays alive briefly until the
            // timeout block runs, but this path is only used once (shell env fallback).
            if let timeoutSeconds {
                DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(timeoutSeconds)) {
                    if process.isRunning {
                        process.terminate()
                    }
                }
            }
        }
    }
}
