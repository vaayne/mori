import Foundation
import XCTest

@testable import MoriRemoteTerminal

@MainActor
final class TmuxSessionLinkWriteFailureTests: XCTestCase {
    func testSendFailureInvalidatesTransportBeforeDisconnectingController() async throws {
        let runtime = try GhosttyKitRuntime()
        let stateRecorder = SessionStateRecorder()
        let transport = LinkTestTransport(failWrites: true)
        let controller = TmuxSessionController(
            callbacks: TmuxSessionController.Callbacks(
                onState: { state in
                    stateRecorder.append(state)
                }
            )
        )
        let link = TmuxSessionLink(controller: controller, transport: transport)

        try await link.start(viewport: .default)

        try await waitUntil("transport was not invalidated after send failure") {
            await transport.closeDispositions().first == .invalidated
        }
        try await waitUntil("controller did not publish transportClosed after send failure") {
            stateRecorder.contains(.detached(.transportClosed))
        }

        await link.stop()
        let closeDispositions = await transport.closeDispositions()
        XCTAssertEqual(closeDispositions, [.invalidated])
        await withCheckedContinuation { continuation in
            controller.shutdown { continuation.resume() }
        }
        withExtendedLifetime(runtime) {}
    }

    func testExplicitStopDoesNotPublishTransportClosed() async throws {
        let runtime = try GhosttyKitRuntime()
        let stateRecorder = SessionStateRecorder()
        let transport = LinkTestTransport(failWrites: false)
        let controller = TmuxSessionController(
            callbacks: TmuxSessionController.Callbacks(
                onState: { state in
                    stateRecorder.append(state)
                }
            )
        )
        let link = TmuxSessionLink(controller: controller, transport: transport)

        try await link.start(viewport: .default)
        try await waitUntil("startup commands were not sent") {
            await transport.sendCount() > 0
        }

        await link.stop()
        await withCheckedContinuation { continuation in
            controller.shutdown { continuation.resume() }
        }

        XCTAssertFalse(stateRecorder.contains(.detached(.transportClosed)))
        let closeDispositions = await transport.closeDispositions()
        XCTAssertEqual(closeDispositions, [.reusable])
        withExtendedLifetime(runtime) {}
    }

    func testUnexpectedReadEndInvalidatesTransportBeforeDisconnectingController() async throws {
        let runtime = try GhosttyKitRuntime()
        let stateRecorder = SessionStateRecorder()
        let transport = LinkTestTransport(failWrites: false)
        let controller = TmuxSessionController(
            callbacks: TmuxSessionController.Callbacks(
                onState: { state in
                    stateRecorder.append(state)
                }
            )
        )
        let link = TmuxSessionLink(controller: controller, transport: transport)

        try await link.start(viewport: .default)
        await transport.finishInput()

        try await waitUntil("transport was not invalidated after read end") {
            await transport.closeDispositions().first == .invalidated
        }
        try await waitUntil("controller did not publish transportClosed after read end") {
            stateRecorder.contains(.detached(.transportClosed))
        }

        await link.stop()
        let closeDispositions = await transport.closeDispositions()
        XCTAssertEqual(closeDispositions, [.invalidated])
        await withCheckedContinuation { continuation in
            controller.shutdown { continuation.resume() }
        }
        withExtendedLifetime(runtime) {}
    }

    private func waitUntil(
        _ failureMessage: String,
        timeout: Duration = .seconds(2),
        condition: () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail(failureMessage)
    }
}

private final class SessionStateRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var states: [TmuxSessionController.SessionState] = []

    func append(_ state: TmuxSessionController.SessionState) {
        lock.lock()
        defer { lock.unlock() }
        states.append(state)
    }

    func contains(_ state: TmuxSessionController.SessionState) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return states.contains(state)
    }
}

private actor LinkTestTransport: TmuxControlTransport {
    enum SendFailure: Error {
        case failed
    }

    nonisolated let receivedBytes: AsyncThrowingStream<Data, Error>

    private let failWrites: Bool
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private var recordedCloseDispositions: [TmuxControlTransportCloseDisposition] = []
    private var recordedSendCount = 0

    init(failWrites: Bool) {
        self.failWrites = failWrites
        var capturedContinuation: AsyncThrowingStream<Data, Error>.Continuation?
        receivedBytes = AsyncThrowingStream { continuation in
            capturedContinuation = continuation
        }
        continuation = capturedContinuation!
    }

    func start(initialViewport: TmuxControlViewport?) async throws {
        _ = initialViewport
        continuation.yield(
            Data("%begin 1 1 0\n%end 1 1 0\n%session-changed $42 main\n".utf8)
        )
    }

    func send(_ data: Data) async throws {
        _ = data
        recordedSendCount += 1
        if failWrites {
            throw SendFailure.failed
        }
    }

    func close(disposition: TmuxControlTransportCloseDisposition) async {
        recordedCloseDispositions.append(disposition)
        continuation.finish()
    }

    func closeDispositions() -> [TmuxControlTransportCloseDisposition] {
        recordedCloseDispositions
    }

    func sendCount() -> Int {
        recordedSendCount
    }

    func finishInput() {
        continuation.finish()
    }
}
