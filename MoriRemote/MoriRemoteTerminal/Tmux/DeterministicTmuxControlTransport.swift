import Foundation

actor DeterministicTmuxControlTransport: TmuxControlTransport {
    nonisolated let receivedBytes: AsyncThrowingStream<Data, Error>

    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private let chunks: [Data]
    private var started = false
    private var sentCommands: [Data] = []

    init(chunks: [Data]) {
        self.chunks = chunks

        var capturedContinuation: AsyncThrowingStream<Data, Error>.Continuation?
        receivedBytes = AsyncThrowingStream { continuation in
            capturedContinuation = continuation
        }
        continuation = capturedContinuation!
    }

    func start(initialViewport: TmuxControlViewport?) async throws {
        _ = initialViewport
        guard !started else { return }
        started = true

        for chunk in chunks {
            continuation.yield(chunk)
        }
    }

    func send(_ data: Data) async throws {
        sentCommands.append(data)
    }

    func close(disposition: TmuxControlTransportCloseDisposition) async {
        _ = disposition
        continuation.finish()
    }

    func commandsSentByGhostty() -> [Data] {
        sentCommands
    }
}
