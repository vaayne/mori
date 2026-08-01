import Foundation
import MoriRemoteTerminal

/// The Phase 2 vertical transport. Startup mutations deliberately happen on separate
/// no-PTY exec children: version probe, grouped shadow creation, then the long-lived
/// `tmux -C` child. A rejected/old probe therefore cannot create a tmux session.
actor SSHTmuxControlTransport {
    nonisolated let receivedBytes: AsyncThrowingStream<Data, Error>

    private enum Lifecycle: Equatable { case idle, starting, started, closing, closed }

    private let connector: any SSHRootConnecting
    private let pool: SSHRootPool
    private let poolKey: SSHRootPool.Key
    private let tmuxExecutable: String
    private let sourceSession: String
    private let runtimeID: UUID
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation

    private var lease: SSHRootLease?
    private var control: (any SSHChildChannel)?
    private var controlReader: Task<Void, Never>?
    /// The startup command may be awaiting output when close wins. Retaining it
    /// lets close unblock and release that child instead of stranding it on root.
    private var startupChild: (any SSHChildChannel)?
    private var shadowCreated = false
    private var lifecycle: Lifecycle = .idle

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

    nonisolated func asTerminalTransport() -> MoriRemoteTerminalTransport {
        MoriRemoteTerminalTransport(
            receivedBytes: receivedBytes,
            start: { try await self.start() },
            send: { try await self.send($0) },
            close: { disposition in
                await self.close(disposition: disposition)
            },
            isActive: { await self.isActive() }
        )
    }

    func start() async throws {
        guard lifecycle != .closed && lifecycle != .closing else { throw SSHTmuxControlTransportError.closed }
        guard lifecycle == .idle else { throw SSHTmuxControlTransportError.alreadyStarted }
        lifecycle = .starting

        do {
            let lease = try await pool.lease(for: poolKey, connector: connector)
            guard lifecycle == .starting else {
                // close won before this healthy shared root was installed here;
                // return its lease to the pool instead of tearing down peers.
                await lease.release(.reusable)
                throw SSHTmuxControlTransportError.closed
            }
            self.lease = lease

            let preflight = try TmuxCommandBuilder.preflight(executable: tmuxExecutable)
            let version = try await run(command: preflight, root: lease.root, trackStartup: true)
            try requireStarting()
            try TmuxCommandBuilder.requireSupportedVersion(version)

            let shadow = try TmuxCommandBuilder.createShadow(
                executable: tmuxExecutable,
                source: sourceSession,
                runtimeID: runtimeID
            )
            _ = try await run(command: shadow, root: lease.root, trackStartup: true)
            try requireStarting()
            shadowCreated = true

            let attach = try TmuxCommandBuilder.attachShadow(
                executable: tmuxExecutable,
                shadow: try TmuxCommandBuilder.shadowName(source: sourceSession, runtimeID: runtimeID)
            )
            let control = try await lease.root.openSessionChannel()
            guard lifecycle == .starting else {
                try? await control.close()
                throw SSHTmuxControlTransportError.closed
            }
            self.control = control
            try await control.execute(attach)
            guard lifecycle == .starting else {
                // close() claims and clears this property before it awaits. Do
                // not double-close an attach channel after the close race won.
                if self.control === control {
                    self.control = nil
                    try? await control.close()
                }
                throw SSHTmuxControlTransportError.closed
            }
            lifecycle = .started
            let receivedBytes = control.receivedBytes
            controlReader = Task { [weak self] in
                do {
                    for try await bytes in receivedBytes {
                        await self?.forwardControlBytes(bytes)
                    }
                    await self?.controlStreamEnded(error: nil)
                } catch {
                    await self?.controlStreamEnded(error: error)
                }
            }
        } catch {
            // Preserve authentication, trust, and tmux startup errors for the
            // root model. Only a concurrent explicit close changes the error to
            // `.closed`; otherwise TOFU would be unreachable from the UI.
            if lifecycle == .starting {
                await terminate(disposition: .invalidated, error: error)
                throw error
            }
            throw SSHTmuxControlTransportError.closed
        }
    }

    private func forwardControlBytes(_ bytes: Data) {
        guard lifecycle == .started else { return }
        continuation.yield(bytes)
    }

    private func controlStreamEnded(error: Error?) async {
        guard lifecycle == .started else { return }
        controlReader = nil
        await terminate(disposition: .invalidated, error: error)
    }

    func send(_ data: Data) async throws {
        guard lifecycle == .started, let control else { throw SSHTmuxControlTransportError.closed }
        do {
            try await control.write(data)
        } catch {
            await terminate(disposition: .invalidated, error: error)
            throw error
        }
    }

    func isActive() async -> Bool {
        guard lifecycle == .started, let control else { return false }
        return await control.isActive()
    }

    func close(disposition: MoriRemoteTerminalCloseDisposition) async {
        guard lifecycle != .closed && lifecycle != .closing else { return }
        await terminate(disposition: disposition, error: nil)
    }

    private func requireStarting() throws {
        guard lifecycle == .starting else { throw SSHTmuxControlTransportError.closed }
    }

    private func run(command: String, root: any SSHRootConnection, trackStartup: Bool = false) async throws -> String {
        let child = try await root.openSessionChannel()
        if trackStartup {
            guard lifecycle == .starting else {
                try? await child.close()
                throw SSHTmuxControlTransportError.closed
            }
            startupChild = child
        }
        do {
            try await child.execute(command)
            if trackStartup { try requireStarting() }
            var output = Data()
            for try await bytes in child.receivedBytes {
                if trackStartup { try requireStarting() }
                output.append(bytes)
            }
            if trackStartup { try requireStarting() }
            let ownsChild = !trackStartup || startupChild === child
            if ownsChild { try? await child.close() }
            if trackStartup, ownsChild { startupChild = nil }
            return String(decoding: output, as: UTF8.self)
        } catch {
            // close() clears startupChild before awaiting child.close(). A resumed
            // startup must not close the same newly acquired child a second time.
            let ownsChild = !trackStartup || startupChild === child
            if ownsChild { try? await child.close() }
            if trackStartup, ownsChild { startupChild = nil }
            throw error
        }
    }

    /// A mismatch is intentionally non-destructive. Root loss merely leaves an owned
    /// disposable shadow behind; it never risks killing the source workspace.
    private func cleanupShadowIfPossible(using lease: SSHRootLease) async -> MoriRemoteTerminalCloseDisposition {
        guard shadowCreated else { return .reusable }
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

    /// Claim closing synchronously before the first await. Every caller then sees a
    /// closed transport while this method releases channels, shadow, lease, and stream.
    private func terminate(disposition: MoriRemoteTerminalCloseDisposition, error: Error?) async {
        guard lifecycle != .closed && lifecycle != .closing else { return }
        lifecycle = .closing
        let control = self.control
        let controlReader = self.controlReader
        let startupChild = self.startupChild
        let lease = self.lease
        self.control = nil
        self.controlReader = nil
        self.startupChild = nil
        self.lease = nil

        controlReader?.cancel()
        if let control { try? await control.close() }
        if let startupChild { try? await startupChild.close() }
        var finalDisposition = disposition
        if let lease {
            let cleanup = await cleanupShadowIfPossible(using: lease)
            if cleanup == .invalidated { finalDisposition = .invalidated }
            await lease.release(finalDisposition)
        }
        lifecycle = .closed
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
