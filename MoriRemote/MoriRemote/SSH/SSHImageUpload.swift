import Foundation
import MoriRemoteTerminal
import NIOCore

extension SSHFileUploadError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unsupported: String(localized: "This SSH connection cannot upload files.")
        case .invalidFilename: String(localized: "The image filename is invalid.")
        case .localFileUnavailable: String(localized: "The local image is no longer available.")
        case .operationTimedOut: String(localized: "The image upload timed out.")
        case .uploadFailed: String(localized: "The image upload failed.")
        }
    }
}

private final class SSHUploadTimeoutGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var pendingResult: Result<Value, Error>?
    private var tasks: [Task<Void, Never>] = []
    private var finished = false

    func install(_ continuation: CheckedContinuation<Value, Error>) {
        let pending = lock.withLock { () -> Result<Value, Error>? in
            if finished { return pendingResult }
            self.continuation = continuation
            return nil
        }
        if let pending { continuation.resume(with: pending) }
    }

    func setTasks(_ tasks: [Task<Void, Never>]) {
        let cancel = lock.withLock { () -> [Task<Void, Never>] in
            if finished { return tasks }
            self.tasks = tasks
            return []
        }
        cancel.forEach { $0.cancel() }
    }

    func succeed(_ value: Value) -> Bool { finish(.success(value)) }
    func fail(_ error: Error) -> Bool { finish(.failure(error)) }
    func cancel() { _ = fail(CancellationError()) }

    func beginTimeout() -> Bool {
        let cancel = lock.withLock { () -> [Task<Void, Never>]? in
            guard !finished else { return nil }
            finished = true
            let tasks = self.tasks
            self.tasks.removeAll()
            return tasks
        }
        guard let cancel else { return false }
        cancel.forEach { $0.cancel() }
        return true
    }

    func finishTimeout() {
        let result = Result<Value, Error>.failure(SSHFileUploadError.operationTimedOut)
        let continuation = lock.withLock { () -> CheckedContinuation<Value, Error>? in
            pendingResult = result
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume(with: result)
    }

    private func finish(_ result: Result<Value, Error>) -> Bool {
        let completion = lock.withLock { () -> (CheckedContinuation<Value, Error>?, [Task<Void, Never>])? in
            guard !finished else { return nil }
            finished = true
            pendingResult = result
            let continuation = self.continuation
            self.continuation = nil
            let tasks = self.tasks
            self.tasks.removeAll()
            return (continuation, tasks)
        }
        guard let completion else { return false }
        completion.1.forEach { $0.cancel() }
        completion.0?.resume(with: result)
        return true
    }
}

enum SSHUploadTimeout {
    static func run<Value: Sendable>(
        timeout: TimeAmount,
        operation: @escaping @Sendable () async throws -> Value,
        onTimeout: @escaping @Sendable () async -> Void = {},
        cleanupLateSuccess: @escaping @Sendable (Value) async -> Void = { _ in }
    ) async throws -> Value {
        let gate = SSHUploadTimeoutGate<Value>()
        let nanoseconds = UInt64(clamping: timeout.nanoseconds)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                gate.install(continuation)
                let operationTask = Task {
                    do {
                        let value = try await operation()
                        if !gate.succeed(value) { await cleanupLateSuccess(value) }
                    } catch {
                        _ = gate.fail(error)
                    }
                }
                let timeoutTask = Task {
                    do {
                        try await Task.sleep(nanoseconds: nanoseconds)
                        if gate.beginTimeout() {
                            await onTimeout()
                            gate.finishTimeout()
                        }
                    } catch is CancellationError {
                        return
                    } catch {
                        _ = gate.fail(error)
                    }
                }
                gate.setTasks([operationTask, timeoutTask])
            }
        } onCancel: {
            gate.cancel()
        }
    }
}

struct SSHImageUploadPaths: Equatable, Sendable {
    let directory: String
    let temporary: String
    let final: String
    let terminal: String
}

struct SSHImageUploadPathBuilder: Sendable {
    static let remoteRoot = ".cache/mori/attachments"
    static let terminalRoot = "~/.cache/mori/attachments"

    func paths(workspaceID: UUID, transferID: UUID, filename: String) throws -> SSHImageUploadPaths {
        let sanitized = sanitize(filename)
        guard !sanitized.isEmpty else { throw SSHFileUploadError.invalidFilename }
        let directory = "\(Self.remoteRoot)/\(workspaceID.uuidString.lowercased())/\(transferID.uuidString.lowercased())"
        let terminalDirectory = "\(Self.terminalRoot)/\(workspaceID.uuidString.lowercased())/\(transferID.uuidString.lowercased())"
        return SSHImageUploadPaths(
            directory: directory,
            temporary: "\(directory)/.\(sanitized).part",
            final: "\(directory)/\(sanitized)",
            terminal: "\(terminalDirectory)/\(sanitized)"
        )
    }

    func directoryPrefixes(_ path: String) -> [String] {
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        return components.indices.map { components[...$0].joined(separator: "/") }
    }

    private func sanitize(_ value: String) -> String {
        let cleaned = value.unicodeScalars.map { scalar -> Character in
            scalar.value < 0x20 || scalar == "/" || scalar == "\\" || scalar == "\0"
                ? "_" : Character(scalar)
        }
        let result = String(cleaned)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "._")))
        return result.isEmpty ? "image" : String(result.prefix(180))
    }
}

enum SSHImageUploadTransfer {
    static func run(
        session: any SSHFileUploadSession,
        localURL: URL,
        paths: SSHImageUploadPaths,
        totalBytes: Int64,
        progress: @escaping MoriRemoteTerminalImageUploader.ProgressHandler
    ) async throws {
        let builder = SSHImageUploadPathBuilder()
        for directory in builder.directoryPrefixes(paths.directory) {
            try await session.ensureDirectoryExists(atPath: directory)
        }
        try? await session.removeFileIfExists(atPath: paths.temporary)
        try await session.uploadFile(from: localURL, to: paths.temporary) { uploaded in
            await progress(uploaded, totalBytes)
        }
        try await session.renameFile(from: paths.temporary, to: paths.final)
    }
}

struct SSHImageUploadService: Sendable {
    let library: RemoteLibrary
    let roots: SSHRootPool
    let trustedHosts: TrustedHostStore

    func uploader(for workspaceID: UUID) -> MoriRemoteTerminalImageUploader {
        MoriRemoteTerminalImageUploader { localURL, filename, progress in
            try await upload(
                workspaceID: workspaceID,
                localURL: localURL,
                filename: filename,
                progress: progress
            )
        }
    }

    private func upload(
        workspaceID: UUID,
        localURL: URL,
        filename: String,
        progress: @escaping MoriRemoteTerminalImageUploader.ProgressHandler
    ) async throws -> String {
        try Task.checkCancellation()
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            throw SSHFileUploadError.localFileUnavailable
        }
        let totalBytes = (try FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        let material = try await library.connectionMaterial(for: workspaceID)
        let auth = try await library.resolveAuth(server: material.1, identity: material.2, settings: material.3)
        let endpoint = try CanonicalEndpoint(host: material.1.host, port: material.1.port)
        let key = SSHRootPool.Key(
            serverID: material.1.id,
            endpoint: endpoint,
            username: material.1.username,
            authenticationFingerprint: auth.rootPoolFingerprint
        )
        let connector = CitadelSSHRootConnector(
            server: material.1,
            auth: auth,
            trust: SSHHostTrustResolver(store: trustedHosts)
        )
        let lease = try await roots.lease(for: key, connector: connector)
        let session: any SSHFileUploadSession
        do {
            session = try await lease.root.openFileUploadSession()
        } catch {
            await lease.release(.reusable)
            throw error
        }

        let paths = try SSHImageUploadPathBuilder().paths(
            workspaceID: workspaceID,
            transferID: UUID(),
            filename: filename
        )
        do {
            try await SSHImageUploadTransfer.run(
                session: session,
                localURL: localURL,
                paths: paths,
                totalBytes: totalBytes,
                progress: progress
            )
            try await session.close()
            await lease.release(.reusable)
            await progress(totalBytes, totalBytes)
            return paths.terminal
        } catch {
            try? await session.removeFileIfExists(atPath: paths.temporary)
            let closeSucceeded: Bool
            do {
                try await session.close()
                closeSucceeded = true
            } catch {
                closeSucceeded = false
            }
            await lease.release(closeSucceeded ? .reusable : .invalidated)
            throw error
        }
    }

}
