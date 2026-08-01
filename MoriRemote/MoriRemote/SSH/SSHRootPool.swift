import Foundation

protocol SSHChildChannel: AnyObject, Sendable {
    var receivedBytes: AsyncThrowingStream<Data, Error> { get }
    func execute(_ command: String) async throws
    func write(_ data: Data) async throws
    func isActive() async -> Bool
    func close() async throws
}

protocol SSHRootConnection: Sendable {
    func openSessionChannel() async throws -> any SSHChildChannel
    func close() async
}

protocol SSHRootConnecting: Sendable {
    func connect() async throws -> any SSHRootConnection
}

enum SSHRootPoolError: Error, Equatable, Sendable {
    case staleLease
}

/// Shares authenticated SSH roots while preserving lease ownership. A generation token
/// prevents an old failed connect or idle timer from deleting a newer replacement.
actor SSHRootPool {
    static let maximumChildren = 4

    struct Key: Hashable, Sendable {
        let serverID: UUID
        let endpoint: CanonicalEndpoint
        let username: String
        let authenticationFingerprint: String
    }

    private struct Entry {
        let token: UUID
        let rootTask: Task<any SSHRootConnection, Error>
        var leases: Int
        var reservations: Int
        var idleClose: Task<Void, Never>?
    }

    private struct RetiredEntry {
        let rootTask: Task<any SSHRootConnection, Error>
        var leases: Int
    }

    private let idleTimeout: Duration
    private var entries: [Key: Entry] = [:]
    private var retired: [UUID: RetiredEntry] = [:]

    init(idleTimeout: Duration = .seconds(120)) {
        self.idleTimeout = idleTimeout
    }

    func lease(for key: Key, connector: any SSHRootConnecting) async throws -> SSHRootLease {
        let entry: Entry
        if var existing = entries[key], existing.leases + existing.reservations < Self.maximumChildren {
            existing.idleClose?.cancel()
            existing.idleClose = nil
            existing.reservations += 1
            entries[key] = existing
            entry = existing
        } else if entries[key] == nil {
            let token = UUID()
            let task = Task { try await connector.connect() }
            entry = Entry(token: token, rootTask: task, leases: 0, reservations: 1, idleClose: nil)
            entries[key] = entry
            observeConnection(task, key: key, token: token)
        } else {
            // Four consumers is the sharing ceiling, not a connection limit. A
            // dedicated root avoids one busy workspace blocking another.
            let root = try await connector.connect()
            return SSHRootLease(key: nil, pool: self, root: root, token: nil)
        }

        do {
            let root = try await entry.rootTask.value
            guard var current = entries[key], current.token == entry.token else {
                await root.close()
                throw SSHRootPoolError.staleLease
            }
            current.reservations -= 1
            current.leases += 1
            entries[key] = current
            return SSHRootLease(key: key, pool: self, root: root, token: entry.token)
        } catch {
            releaseReservation(key: key, token: entry.token)
            throw error
        }
    }

    fileprivate func release(_ lease: SSHRootLease, disposition: TmuxControlTransportCloseDisposition) async {
        guard let key = lease.key, let token = lease.token else {
            await lease.root.close()
            return
        }
        guard var entry = entries[key], entry.token == token else {
            if var old = retired[token] {
                old.leases -= 1
                if old.leases == 0 {
                    retired[token] = nil
                    await lease.root.close()
                } else {
                    retired[token] = old
                }
            }
            return
        }

        entry.leases = max(0, entry.leases - 1)
        if disposition == .invalidated {
            entry.idleClose?.cancel()
            entries[key] = nil
            if entry.leases == 0 {
                await lease.root.close()
            } else {
                retired[token] = RetiredEntry(rootTask: entry.rootTask, leases: entry.leases)
            }
            return
        }

        entries[key] = entry
        scheduleIdleClose(for: key, token: token)
    }

    private func releaseReservation(key: Key, token: UUID) {
        guard var entry = entries[key], entry.token == token else { return }
        entry.reservations = max(0, entry.reservations - 1)
        entries[key] = entry
        scheduleIdleClose(for: key, token: token)
    }

    private func observeConnection(_ task: Task<any SSHRootConnection, Error>, key: Key, token: UUID) {
        Task {
            do {
                _ = try await task.value
            } catch {
                guard let entry = self.entries[key], entry.token == token else { return }
                entry.idleClose?.cancel()
                self.entries[key] = nil
            }
        }
    }

    private func scheduleIdleClose(for key: Key, token: UUID) {
        guard var entry = entries[key], entry.token == token,
              entry.leases == 0, entry.reservations == 0 else { return }
        entry.idleClose?.cancel()
        entry.idleClose = Task { [weak self, idleTimeout] in
            do {
                try await Task.sleep(for: idleTimeout)
                await self?.closeIdle(key: key, token: token)
            } catch {
                return
            }
        }
        entries[key] = entry
    }

    private func closeIdle(key: Key, token: UUID) async {
        guard let entry = entries[key], entry.token == token,
              entry.leases == 0, entry.reservations == 0 else { return }
        entries[key] = nil
        if let root = try? await entry.rootTask.value {
            await root.close()
        }
    }
}

private final class SSHRootLeaseReleaseState: @unchecked Sendable {
    private let lock = NSLock()
    private var released = false

    func claim() -> Bool {
        lock.withLock {
            guard !released else { return false }
            released = true
            return true
        }
    }
}

struct SSHRootLease: Sendable {
    fileprivate let key: SSHRootPool.Key?
    fileprivate let pool: SSHRootPool
    let root: any SSHRootConnection
    fileprivate let token: UUID?
    private let releaseState = SSHRootLeaseReleaseState()

    fileprivate init(key: SSHRootPool.Key?, pool: SSHRootPool, root: any SSHRootConnection, token: UUID?) {
        self.key = key
        self.pool = pool
        self.root = root
        self.token = token
    }

    func release(_ disposition: TmuxControlTransportCloseDisposition) async {
        let shouldRelease = releaseState.claim()
        guard shouldRelease else { return }
        await pool.release(self, disposition: disposition)
    }
}
