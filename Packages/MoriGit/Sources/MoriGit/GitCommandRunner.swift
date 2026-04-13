import Foundation
import MoriCore

/// SSH configuration for running git commands on a remote host.
public typealias GitSSHConfig = SSHExecutionConfig

/// Runs git commands via `Process` (Foundation).
/// Resolves the git binary path via PATH lookup with common fallback locations.
public actor GitCommandRunner {

    /// Cached path to the git binary, resolved on first use.
    private var resolvedBinaryPath: String?
    private let sshConfig: GitSSHConfig?

    private enum ProcessExecutionError: Error, Sendable {
        case timedOut(Int)
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

    public init(sshConfig: GitSSHConfig? = nil) {
        self.sshConfig = sshConfig
    }

    // MARK: - Binary Resolution

    /// Resolve the git binary path through the shared binary resolver.
    public func resolveBinaryPath() async throws -> String {
        if sshConfig != nil {
            return "git"
        }
        if let cached = resolvedBinaryPath {
            return cached
        }

        if let path = BinaryResolver.resolve(command: "git") {
            resolvedBinaryPath = path
            return path
        }

        throw GitError.binaryNotFound
    }

    /// Check if git is available on this system.
    public func isAvailable() async -> Bool {
        if sshConfig != nil {
            do {
                _ = try await run(["--version"])
                return true
            } catch {
                return false
            }
        }
        do {
            _ = try await resolveBinaryPath()
            return true
        } catch {
            return false
        }
    }

    // MARK: - Command Execution

    /// Run a git command with the given arguments. Returns stdout as a string.
    public func run(_ arguments: String...) async throws -> String {
        try await run(arguments)
    }

    /// Run a git command with the given arguments array. Returns stdout as a string.
    public func run(_ arguments: [String]) async throws -> String {
        if let sshConfig {
            let remoteCommand = (["git"] + arguments).map(SSHCommandSupport.shellEscape).joined(separator: " ")
            var sshArguments: [String] = SSHCommandSupport.connectivityOptions()
            sshArguments += sshConfig.sshOptions
            if let port = sshConfig.port {
                sshArguments += ["-p", "\(port)"]
            }
            sshArguments += [sshConfig.target, remoteCommand]

            var stdout: String
            var exitCode: Int32
            do {
                (stdout, exitCode) = try await runProcess(
                    executablePath: "/usr/bin/ssh",
                    arguments: sshArguments,
                    timeoutSeconds: SSHCommandSupport.remoteCommandTimeoutSeconds
                )
            } catch ProcessExecutionError.timedOut(let seconds) {
                let cmd = "ssh \(sshConfig.target) \(remoteCommand)"
                throw GitError.executionFailed(
                    command: cmd,
                    exitCode: 124,
                    stderr: "SSH command timed out after \(seconds)s."
                )
            }

            if exitCode == 255,
               let password = sshConfig.askpassPassword,
               !password.isEmpty {
                try await bootstrapPasswordControlMaster(sshConfig: sshConfig, password: password)
                do {
                    (stdout, exitCode) = try await runProcess(
                        executablePath: "/usr/bin/ssh",
                        arguments: sshArguments,
                        timeoutSeconds: SSHCommandSupport.remoteCommandTimeoutSeconds
                    )
                } catch ProcessExecutionError.timedOut(let seconds) {
                    let cmd = "ssh \(sshConfig.target) \(remoteCommand)"
                    throw GitError.executionFailed(
                        command: cmd,
                        exitCode: 124,
                        stderr: "SSH command timed out after \(seconds)s."
                    )
                }
            }

            if exitCode != 0 {
                let cmd = "ssh \(sshConfig.target) \(remoteCommand)"
                throw GitError.executionFailed(command: cmd, exitCode: exitCode, stderr: stdout)
            }

            return stdout
        }

        let binaryPath = try await resolveBinaryPath()
        let (stdout, exitCode) = try await runProcess(
            executablePath: binaryPath,
            arguments: arguments
        )

        if exitCode != 0 {
            let cmd = "git \(arguments.joined(separator: " "))"
            throw GitError.executionFailed(command: cmd, exitCode: exitCode, stderr: stdout)
        }

        return stdout
    }

    /// Run a git command in a specific working directory.
    public func run(in directory: String, _ arguments: [String]) async throws -> String {
        try await run(["-C", directory] + arguments)
    }

    /// Ensure a directory exists on the execution host.
    /// Local: `FileManager.createDirectory`.
    /// Remote: `ssh ... "mkdir -p <path>"`.
    public func ensureDirectory(path: String) async throws {
        if let sshConfig {
            let remoteCommand = "mkdir -p \(SSHCommandSupport.shellEscape(path))"
            var sshArguments: [String] = SSHCommandSupport.connectivityOptions()
            sshArguments += sshConfig.sshOptions
            if let port = sshConfig.port {
                sshArguments += ["-p", "\(port)"]
            }
            sshArguments += [sshConfig.target, remoteCommand]

            var output: String
            var exitCode: Int32
            do {
                (output, exitCode) = try await runProcess(
                    executablePath: "/usr/bin/ssh",
                    arguments: sshArguments,
                    timeoutSeconds: SSHCommandSupport.remoteCommandTimeoutSeconds
                )
            } catch ProcessExecutionError.timedOut(let seconds) {
                let cmd = "ssh \(sshConfig.target) \(remoteCommand)"
                throw GitError.executionFailed(
                    command: cmd,
                    exitCode: 124,
                    stderr: "SSH command timed out after \(seconds)s."
                )
            }

            if exitCode == 255,
               let password = sshConfig.askpassPassword,
               !password.isEmpty {
                try await bootstrapPasswordControlMaster(sshConfig: sshConfig, password: password)
                do {
                    (output, exitCode) = try await runProcess(
                        executablePath: "/usr/bin/ssh",
                        arguments: sshArguments,
                        timeoutSeconds: SSHCommandSupport.remoteCommandTimeoutSeconds
                    )
                } catch ProcessExecutionError.timedOut(let seconds) {
                    let cmd = "ssh \(sshConfig.target) \(remoteCommand)"
                    throw GitError.executionFailed(
                        command: cmd,
                        exitCode: 124,
                        stderr: "SSH command timed out after \(seconds)s."
                    )
                }
            }

            if exitCode != 0 {
                let cmd = "ssh \(sshConfig.target) \(remoteCommand)"
                throw GitError.executionFailed(command: cmd, exitCode: exitCode, stderr: output)
            }
            return
        }

        do {
            try FileManager.default.createDirectory(
                atPath: path,
                withIntermediateDirectories: true
            )
        } catch {
            throw GitError.executionFailed(
                command: "mkdir -p \(path)",
                exitCode: 1,
                stderr: error.localizedDescription
            )
        }
    }

    // MARK: - Private

    private func runProcess(
        executablePath: String,
        arguments: [String],
        environment: [String: String]? = nil,
        stdinNull: Bool = false,
        timeoutSeconds: Int? = nil
    ) async throws -> (output: String, exitCode: Int32) {
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
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                // Prefer stderr for error messages, fall back to stdout
                let output = stderr.isEmpty ? stdout : stderr
                guard_.resume(with: .success((output, process.terminationStatus)))
            }

            if let timeoutSeconds {
                DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(timeoutSeconds)) {
                    if process.isRunning {
                        process.terminate()
                        guard_.resume(with: .failure(ProcessExecutionError.timedOut(timeoutSeconds)))
                    }
                }
            }
        }
    }

    private func bootstrapPasswordControlMaster(
        sshConfig: GitSSHConfig,
        password: String
    ) async throws {
        let askPassScript = try SSHCommandSupport.createAskPassScript(password: password)
        defer { askPassScript.cleanup() }

        var args: [String] = SSHCommandSupport.connectivityOptions()
        args += SSHCommandSupport.removingBatchMode(from: sshConfig.sshOptions)
        args += [
            "-o", "PreferredAuthentications=password,keyboard-interactive",
            "-o", "PubkeyAuthentication=no",
            "-o", "NumberOfPasswordPrompts=1",
        ]
        if let port = sshConfig.port {
            args += ["-p", "\(port)"]
        }
        args += [sshConfig.target, "exit"]

        let env = SSHCommandSupport.askPassEnvironment(scriptPath: askPassScript.path)

        let output: String
        let exitCode: Int32
        do {
            (output, exitCode) = try await runProcess(
                executablePath: "/usr/bin/ssh",
                arguments: args,
                environment: env,
                stdinNull: true,
                timeoutSeconds: SSHCommandSupport.bootstrapTimeoutSeconds
            )
        } catch ProcessExecutionError.timedOut(let seconds) {
            throw GitError.executionFailed(
                command: "ssh \(sshConfig.target) exit",
                exitCode: 124,
                stderr: "SSH authentication timed out after \(seconds)s."
            )
        }
        guard exitCode == 0 else {
            throw GitError.executionFailed(
                command: "ssh \(sshConfig.target) exit",
                exitCode: exitCode,
                stderr: output.isEmpty ? "SSH authentication failed." : output
            )
        }
    }
}
