import Foundation

/// The Phase 2 vertical transport. Startup mutations deliberately happen on separate
/// no-PTY exec children: version probe, grouped shadow creation, then the long-lived
/// `tmux -C` child. A rejected/old probe therefore cannot create a tmux session.
actor SSHTmuxControlTransport: TmuxControlTransport {
    nonisolated let receivedBytes: AsyncThrowingStream<Data, Error>

    private let connector: any SSHRootConnecting
    private let pool: SSHRootPool
    private let poolKey: SSHRootPool.Key
    private let tmuxExecutable: String
    private let sourceSession: String
    private let runtimeID: UUID
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation

    private var lease: SSHRootLease?
    private var control: (any SSHChildChannel)?
    private var started = false
    private var closed = false

    init(
        connector: any SSHRootConnecting,
        pool: SSHRootPool,
        poolKey: SSHRootPool.Key,
        tmuxExecutable: String = "tmux",
        sourceSession: String,
        runtimeID: UUID = UUID()
    ) {
        self.connector = connector
        self.pool = pool
        self.poolKey = poolKey
        self.tmuxExecutable = tmuxExecutable
        self.sourceSession = sourceSession
        self.runtimeID = runtimeID
        var continuation: AsyncThrowingStream<Data, Error>.Continuation!
        receivedBytes = AsyncThrowingStream { continuation = $0 }
        self.continuation = continuation
    }

    func start() async throws {
        guard !closed else { throw SSHTmuxControlTransportError.closed }
        guard !started else { throw SSHTmuxControlTransportError.alreadyStarted }
        started = true

        do {
            let lease = try await pool.lease(for: poolKey, connector: connector)
            self.lease = lease
            let preflight = try TmuxCommandBuilder.preflight(executable: tmuxExecutable)
            let version = try await run(command: preflight, root: lease.root)
            try TmuxCommandBuilder.requireSupportedVersion(version)

            let shadow = try TmuxCommandBuilder.createShadow(
                executable: tmuxExecutable,
                source: sourceSession,
                runtimeID: runtimeID
            )
            _ = try await run(command: shadow, root: lease.root)

            let attach = try TmuxCommandBuilder.attachShadow(
                executable: tmuxExecutable,
                shadow: try TmuxCommandBuilder.shadowName(source: sourceSession, runtimeID: runtimeID)
            )
            let control = try await lease.root.openSessionChannel()
            try await control.execute(attach)
            self.control = control
        } catch {
            await finish(disposition: .invalidated, error: error)
            throw error
        }
    }

    func send(_ data: Data) async throws {
        guard !closed, let control else { throw SSHTmuxControlTransportError.closed }
        do {
            try await control.write(data)
        } catch {
            await finish(disposition: .invalidated, error: error)
            throw error
        }
    }

    func isActive() async -> Bool {
        guard !closed, let control else { return false }
        return await control.isActive()
    }

    func close(disposition: TmuxControlTransportCloseDisposition) async {
        guard !closed else { return }
        let cleanupDisposition = await cleanupShadowIfPossible()
        await finish(disposition: cleanupDisposition ?? disposition, error: nil)
    }

    private func run(command: String, root: any SSHRootConnection) async throws -> String {
        let child = try await root.openSessionChannel()
        defer { Task { try? await child.close() } }
        try await child.execute(command)
        var output = Data()
        for try await bytes in child.receivedBytes {
            output.append(bytes)
        }
        return String(decoding: output, as: UTF8.self)
    }

    /// A mismatch is intentionally non-destructive. Root loss merely leaves an owned
    /// disposable shadow behind; it never risks killing the source workspace.
    private func cleanupShadowIfPossible() async -> TmuxControlTransportCloseDisposition? {
        guard let lease else { return nil }
        do {
            let plan = try TmuxCommandBuilder.cleanupPlan(
                executable: tmuxExecutable,
                source: sourceSession,
                shadow: try TmuxCommandBuilder.shadowName(source: sourceSession, runtimeID: runtimeID),
                runtimeID: runtimeID
            )
            let output = try await run(command: plan.verifyCommand, root: lease.root)
            try TmuxCommandBuilder.verifyCleanup(output, plan: plan)
            _ = try await run(command: plan.killCommand, root: lease.root)
            return .reusable
        } catch {
            return .invalidated
        }
    }

    private func finish(disposition: TmuxControlTransportCloseDisposition, error: Error?) async {
        guard !closed else { return }
        closed = true
        let control = self.control
        let lease = self.lease
        self.control = nil
        self.lease = nil
        if let control { try? await control.close() }
        if let lease { await lease.release(disposition) }
        continuation.finish(throwing: error)
    }
}

enum SSHTmuxControlTransportError: Error, Equatable, Sendable, LocalizedError {
    case closed
    case alreadyStarted

    var errorDescription: String? {
        switch self {
        case .closed:
            String(localized: "The tmux control connection is closed.")
        case .alreadyStarted:
            String(localized: "The tmux control connection has already started.")
        }
    }
}
