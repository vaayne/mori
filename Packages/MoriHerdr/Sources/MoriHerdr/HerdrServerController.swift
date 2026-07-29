#if os(macOS)
import Foundation

public enum HerdrServerState: Sendable, Hashable {
    case running(version: String, protocolVersion: Int)
    case restarting(reason: String)
    case unavailable(reason: String)
}

/// Keeps a herdr server alive for Mori's session.
///
/// The server deliberately **outlives Mori**, exactly as a tmux server does: quitting the
/// app must not kill the user's shells. So this controller starts a server when none is
/// reachable and never stops one — `stopSupervision` only stops watching.
///
/// "Reachable" is defined by a `ping` over the socket rather than by a child process handle,
/// because the server Mori talks to may well be one an earlier Mori (or the user) started.
public actor HerdrServerController {
    public enum StartFailure: Error, CustomStringConvertible {
        case binaryMissing(String)
        case exitedImmediately(status: Int32, log: String)
        case neverBecameReachable(seconds: TimeInterval, log: String)

        public var description: String {
            switch self {
            case .binaryMissing(let path):
                return "no herdr binary at \(path)"
            case .exitedImmediately(let status, let log):
                return "herdr server exited with status \(status)\(log.isEmpty ? "" : ": \(log)")"
            case .neverBecameReachable(let seconds, let log):
                return "herdr server did not answer within \(Int(seconds))s\(log.isEmpty ? "" : ": \(log)")"
            }
        }
    }

    private let binaryPath: String
    private let environment: HerdrEnvironment
    private let logPath: String?
    private let backend: HerdrBackend

    private var spawned: Process?
    private var supervision: Task<Void, Never>?
    private var continuation: AsyncStream<HerdrServerState>.Continuation?
    private var lastState: HerdrServerState?

    public init(binaryPath: String, environment: HerdrEnvironment, logPath: String? = nil) {
        self.binaryPath = binaryPath
        self.environment = environment
        self.logPath = logPath
        // A short timeout on purpose: this is a local unix socket, so a healthy server
        // answers in milliseconds and an unhealthy one should be declared dead quickly
        // rather than adding the default 5s to every restart.
        backend = HerdrBackend(socketPath: environment.socketPath, timeout: 1)
    }

    public nonisolated var socketPath: String { environment.socketPath }

    /// The server this controller started, if it started one. `nil` when Mori simply
    /// attached to a server that was already running.
    public var spawnedProcessIdentifier: Int32? {
        guard let spawned, spawned.isRunning else { return nil }
        return spawned.processIdentifier
    }

    /// State changes, for callers that need to reattach after a restart. Only transitions are
    /// published — a healthy server that stays healthy is silent.
    public func states() -> AsyncStream<HerdrServerState> {
        continuation?.finish()
        let (stream, continuation) = AsyncStream<HerdrServerState>.makeStream(bufferingPolicy: .unbounded)
        self.continuation = continuation
        if let lastState { continuation.yield(lastState) }
        return stream
    }

    // MARK: - Starting

    /// Idempotent: returns immediately if a server already answers, otherwise starts one.
    @discardableResult
    public func ensureRunning(timeout: TimeInterval = 15) async throws -> HerdrServerInfo {
        if let info = try? await backend.handshake() {
            publish(.running(version: info.version, protocolVersion: info.protocol))
            return info
        }
        return try await startServer(timeout: timeout)
    }

    /// Spawns a server without first checking for one. Only for callers that just
    /// established there is none — skipping the redundant probe is what keeps a restart
    /// inside one supervision interval.
    @discardableResult
    private func startServer(timeout: TimeInterval) async throws -> HerdrServerInfo {
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
            let failure = StartFailure.binaryMissing(binaryPath)
            publish(.unavailable(reason: failure.description))
            throw failure
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["server"]
        process.environment = environment.apply(to: ProcessInfo.processInfo.environment)
        // A log *file*, never a Pipe: nothing here drains a pipe, and a full one would wedge
        // the server the first time it wrote more than the buffer.
        if let handle = try? logHandle() {
            process.standardOutput = handle
            process.standardError = handle
        } else {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }
        try process.run()
        spawned = process

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let info = try? await backend.handshake() {
                publish(.running(version: info.version, protocolVersion: info.protocol))
                return info
            }
            guard process.isRunning else {
                // A server may already have been running and this one bowed out; re-check
                // before blaming it, since that exit is success, not failure.
                if let info = try? await backend.handshake() {
                    publish(.running(version: info.version, protocolVersion: info.protocol))
                    return info
                }
                let failure = StartFailure.exitedImmediately(status: process.terminationStatus, log: logTail())
                publish(.unavailable(reason: failure.description))
                throw failure
            }
            try? await Task.sleep(for: .milliseconds(100))
        }

        let failure = StartFailure.neverBecameReachable(seconds: timeout, log: logTail())
        publish(.unavailable(reason: failure.description))
        throw failure
    }

    // MARK: - Supervision

    /// Polls for liveness and restarts a server that died. Cheap: one socket round-trip
    /// against a local unix socket, so the interval can afford to be short.
    public func startSupervision(interval: Duration = .seconds(3)) {
        supervision?.cancel()
        supervision = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                await self.checkOnce()
            }
        }
    }

    public func stopSupervision() {
        supervision?.cancel()
        supervision = nil
        continuation?.finish()
        continuation = nil
    }

    private func checkOnce() async {
        if let info = try? await backend.handshake() {
            publish(.running(version: info.version, protocolVersion: info.protocol))
            return
        }
        publish(.restarting(reason: "herdr server stopped answering"))
        // `startServer`, not `ensureRunning`: the handshake above already proved it is gone.
        _ = try? await startServer(timeout: 15)
    }

    // MARK: - Plumbing

    private func publish(_ state: HerdrServerState) {
        guard state != lastState else { return }
        lastState = state
        continuation?.yield(state)
    }

    private func logHandle() throws -> FileHandle? {
        guard let logPath else { return nil }
        try FileManager.default.createDirectory(
            atPath: (logPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: logPath))
        try handle.seekToEnd()
        return handle
    }

    /// The last few lines of the log, so a failure says why instead of just that.
    private func logTail(lines: Int = 8) -> String {
        guard let logPath, let contents = try? String(contentsOfFile: logPath, encoding: .utf8) else { return "" }
        return contents.split(separator: "\n").suffix(lines).joined(separator: " / ")
    }
}
#endif
