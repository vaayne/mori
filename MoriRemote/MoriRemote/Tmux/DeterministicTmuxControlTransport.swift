import Foundation

/// Scripted transport for tests and the DEBUG renderer probe. Chunks may be
/// delayed or fail; all accepted writes and terminal errors remain observable.
actor DeterministicTmuxControlTransport: TmuxControlTransport {
    struct Event: Sendable { let delayNanoseconds: UInt64; let chunk: Data?; let error: Error?
        static func chunk(_ string: String, after delayNanoseconds: UInt64 = 0) -> Self { .init(delayNanoseconds: delayNanoseconds, chunk: Data(string.utf8), error: nil) }
        static func failure(_ error: Error, after delayNanoseconds: UInt64 = 0) -> Self { .init(delayNanoseconds: delayNanoseconds, chunk: nil, error: error) }
    }
    nonisolated let receivedBytes: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private let events: [Event]
    private var started = false
    private var writes: [Data] = []
    private var writeError: Error?
    private let holdOpen: Bool

    init(transcript: [String], writeError: Error? = nil, holdOpen: Bool = false) { self.init(events: transcript.map { Event.chunk($0) }, writeError: writeError, holdOpen: holdOpen) }
    init(events: [Event], writeError: Error? = nil, holdOpen: Bool = false) {
        self.events = events; self.writeError = writeError; self.holdOpen = holdOpen
        var captured: AsyncThrowingStream<Data, Error>.Continuation!
        receivedBytes = AsyncThrowingStream { captured = $0 }
        continuation = captured
    }
    func start() async throws {
        guard !started else { return }; started = true
        for event in events {
            if event.delayNanoseconds > 0 { try? await Task.sleep(nanoseconds: event.delayNanoseconds) }
            if let chunk = event.chunk { continuation.yield(chunk) }
            if let error = event.error { continuation.finish(throwing: error); return }
        }
        if !holdOpen && !events.contains(where: { $0.error != nil }) { continuation.finish() }
    }
    func send(_ data: Data) async throws { writes.append(data); if let writeError { throw writeError } }
    func setWriteError(_ error: Error?) { writeError = error }
    func isActive() async -> Bool { started }
    func close(disposition: TmuxControlTransportCloseDisposition) async { _ = disposition; continuation.finish() }
    func sentWrites() -> [Data] { writes }
}
