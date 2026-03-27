import Foundation
import MoriCore

private final class SSHBootstrapResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false
    private let continuation: CheckedContinuation<(stdout: String, stderr: String, code: Int32), any Error>

    init(continuation: CheckedContinuation<(stdout: String, stderr: String, code: Int32), any Error>) {
        self.continuation = continuation
    }

    func resume(with result: sending Result<(stdout: String, stderr: String, code: Int32), any Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        continuation.resume(with: result)
    }
}

enum SSHControlOptions {
    static let controlPersist = "8h"

    static func controlPath(for ssh: SSHWorkspaceLocation) -> String {
        SSHCommandSupport.controlSocketPath(endpointKey: ssh.endpointKey)
    }

    static func sshOptions(for ssh: SSHWorkspaceLocation) -> [String] {
        [
            "-o", "BatchMode=yes",
            "-o", "ControlMaster=auto",
            "-o", "ControlPersist=\(controlPersist)",
            "-o", "ControlPath=\(controlPath(for: ssh))",
        ]
    }
}

enum SSHBootstrapError: LocalizedError {
    case passwordRequired
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .passwordRequired:
            return "Password is required for password authentication."
        case .processFailed(let message):
            return message
        }
    }
}

enum SSHBootstrapper {
    static func bootstrapPasswordSession(
        ssh: SSHWorkspaceLocation,
        password: String?
    ) async throws {
        guard let password, !password.isEmpty else {
            throw SSHBootstrapError.passwordRequired
        }

        let askPassScript = try SSHCommandSupport.createAskPassScript(password: password)
        defer { askPassScript.cleanup() }

        var args: [String] = SSHCommandSupport.connectivityOptions()
        args += [
            "-o", "ControlMaster=auto",
            "-o", "ControlPersist=\(SSHControlOptions.controlPersist)",
            "-o", "ControlPath=\(SSHControlOptions.controlPath(for: ssh))",
            "-o", "PreferredAuthentications=password,keyboard-interactive",
            "-o", "PubkeyAuthentication=no",
            "-o", "NumberOfPasswordPrompts=1",
        ]
        if let port = ssh.port {
            args += ["-p", "\(port)"]
        }
        args += [ssh.target, "exit"]

        let environment = SSHCommandSupport.askPassEnvironment(scriptPath: askPassScript.path)

        let (stdout, stderr, code) = try await runProcess(
            executablePath: "/usr/bin/ssh",
            arguments: args,
            environment: environment,
            timeoutSeconds: SSHCommandSupport.bootstrapTimeoutSeconds
        )

        if code != 0 {
            let message = stderr.isEmpty ? stdout : stderr
            throw SSHBootstrapError.processFailed(message.isEmpty ? "SSH authentication failed." : message)
        }
    }

    private static func runProcess(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        timeoutSeconds: Int? = nil
    ) async throws -> (stdout: String, stderr: String, code: Int32) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            process.environment = environment
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.standardInput = FileHandle.nullDevice

            let guard_ = SSHBootstrapResumeGuard(continuation: continuation)

            do {
                try process.run()
            } catch {
                guard_.resume(with: .failure(error))
                return
            }

            process.terminationHandler = { _ in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                guard_.resume(with: .success((stdout, stderr, process.terminationStatus)))
            }

            if let timeoutSeconds {
                DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(timeoutSeconds)) {
                    if process.isRunning {
                        process.terminate()
                        guard_.resume(with: .failure(SSHBootstrapError.processFailed(
                            "SSH authentication timed out after \(timeoutSeconds)s."
                        )))
                    }
                }
            }
        }
    }
}
