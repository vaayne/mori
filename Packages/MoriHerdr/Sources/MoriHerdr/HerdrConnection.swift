import Foundation
import Network

/// One connection to a herdr socket, framed as newline-delimited JSON.
///
/// Hides `NWConnection`'s callback plumbing, the partial-read buffering NDJSON needs,
/// and the difference between "the peer finished" and "the peer broke". Callers see a
/// single-consumer `nextLine()` that returns `nil` at end of stream.
///
/// Deliberately single-consumer: herdr's protocol is one request per connection for
/// calls and one subscription per connection for streams, so nothing needs to read
/// concurrently. Overlapping `nextLine()` calls are a programming error.
final class HerdrConnection: @unchecked Sendable {
    private let path: String
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "com.mori.herdr.connection")

    private let lock = NSLock()
    private var buffer = Data()
    private var pending: [Data] = []
    private var waiter: CheckedContinuation<Data?, any Error>?
    private var failure: (any Error)?
    private var finished = false
    /// Bumped whenever a deadline is cleared, so a fired timer for an old deadline is ignored.
    private var deadlineGeneration = 0

    init(path: String) {
        self.path = path
        connection = NWConnection(to: .unix(path: path), using: .tcp)
    }

    // MARK: - Lifecycle

    func open(timeout: TimeInterval) async throws {
        let box = ReadyBox()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    box.resumeOnce { continuation.resume() }
                case .failed(let error):
                    box.resumeOnce { continuation.resume(throwing: HerdrError.notConnected(path: self.path, underlying: "\(error)")) }
                case .cancelled:
                    box.resumeOnce { continuation.resume(throwing: HerdrError.notConnected(path: self.path, underlying: "cancelled")) }
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self else { return }
                box.resumeOnce {
                    self.connection.cancel()
                    continuation.resume(throwing: HerdrError.notConnected(path: self.path, underlying: "timed out connecting"))
                }
            }
        }
        connection.stateUpdateHandler = nil
        receiveNext()
    }

    func close() {
        finish(with: nil)
        connection.cancel()
    }

    // MARK: - Deadlines

    /// Tears the connection down if it has not been disarmed by `deadline`.
    ///
    /// Cancelling the connection is what makes the timeout reliable: it forces the
    /// in-flight receive to complete, so no continuation is left dangling.
    func armDeadline(_ seconds: TimeInterval, error: @autoclosure @escaping @Sendable () -> any Error) {
        lock.lock()
        deadlineGeneration += 1
        let generation = deadlineGeneration
        lock.unlock()

        queue.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self else { return }
            lock.lock()
            let stale = generation != deadlineGeneration
            lock.unlock()
            guard !stale else { return }
            finish(with: error())
            connection.cancel()
        }
    }

    func clearDeadline() {
        lock.lock()
        deadlineGeneration += 1
        lock.unlock()
    }

    // MARK: - I/O

    func send(_ payload: Data) async throws {
        var line = payload
        line.append(0x0A)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(content: line, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: HerdrError.notConnected(path: self.path, underlying: "\(error)"))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    /// The next complete line, or `nil` once the peer is done and the buffer is drained.
    ///
    /// The whole decision — buffered line, recorded failure, clean end, or park — happens
    /// inside the continuation body, which is synchronous and so may hold the lock.
    func nextLine() async throws -> Data? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, any Error>) in
            lock.lock()
            if !pending.isEmpty {
                let line = pending.removeFirst()
                lock.unlock()
                continuation.resume(returning: line)
            } else if let failure {
                lock.unlock()
                continuation.resume(throwing: failure)
            } else if finished {
                lock.unlock()
                continuation.resume(returning: nil)
            } else {
                waiter = continuation
                lock.unlock()
            }
        }
    }

    // MARK: - Receive loop

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty { ingest(data) }
            if let error {
                finish(with: HerdrError.notConnected(path: path, underlying: "\(error)"))
                return
            }
            if isComplete {
                finish(with: nil)
                return
            }
            receiveNext()
        }
    }

    private func ingest(_ data: Data) {
        lock.lock()
        buffer.append(data)
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex ..< newline]
            buffer = buffer[buffer.index(after: newline)...]
            if !line.isEmpty { lines.append(Data(line)) }
        }
        guard !lines.isEmpty else {
            lock.unlock()
            return
        }
        buffer = Data(buffer) // re-base: slicing leaves the consumed prefix in the backing store
        pending.append(contentsOf: lines)
        let continuation = takeWaiterLocked()
        let next = continuation != nil ? pending.removeFirst() : nil
        lock.unlock()
        continuation?.resume(returning: next)
    }

    /// Marks the stream done. `error` distinguishes a broken connection from a clean close.
    private func finish(with error: (any Error)?) {
        lock.lock()
        guard !finished, failure == nil else {
            lock.unlock()
            return
        }
        finished = true
        failure = error
        // A clean close after buffered lines is not an error for the reader: it drains first.
        let continuation = takeWaiterLocked()
        let hasPending = !pending.isEmpty
        let next = (continuation != nil && hasPending) ? pending.removeFirst() : nil
        lock.unlock()

        guard let continuation else { return }
        if let next {
            continuation.resume(returning: next)
        } else if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume(returning: nil)
        }
    }

    private func takeWaiterLocked() -> CheckedContinuation<Data?, any Error>? {
        defer { waiter = nil }
        return waiter
    }
}

/// Guards a continuation that several callbacks race to resume.
private final class ReadyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func resumeOnce(_ body: () -> Void) {
        lock.lock()
        guard !done else {
            lock.unlock()
            return
        }
        done = true
        lock.unlock()
        body()
    }
}
