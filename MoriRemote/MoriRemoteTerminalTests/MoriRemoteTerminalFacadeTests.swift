import Foundation
import XCTest
@testable import MoriRemoteTerminal

@MainActor
final class MoriRemoteTerminalFacadeTests: XCTestCase {
    func testStartFailurePublishesDisconnectedStateAndError() async throws {
        let session = try MoriRemoteTerminalSession(transport: failingTransport())
        session.prepareInitialViewport(size: CGSize(width: 320, height: 480), scale: 2)

        do {
            try await session.start()
            XCTFail("expected transport start failure")
        } catch {
            XCTAssertEqual(session.connectionState, .disconnected)
            XCTAssertEqual(session.lastError, "synthetic transport failure")
        }
        await session.stop()
    }

    func testLateSyncCannotRegressRenderedTopologyToConnecting() {
        XCTAssertEqual(
            MoriRemoteTerminalConnectionProjection.applying(.connecting, hasTopology: true),
            .ready
        )
        XCTAssertEqual(
            MoriRemoteTerminalConnectionProjection.applying(.connecting, hasTopology: false),
            .connecting
        )
    }

    func testStoppedSessionReturnsFixedFailedMetadataResult() async throws {
        let session = try MoriRemoteTerminalSession(transport: inertTransport())
        await session.stop()

        let result = await session.queryAgentMetadata()
        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.body, "")
    }

    func testCancelledStartBeforeViewportDoesNotStartTransport() async throws {
        let recorder = FacadeStartRecorder()
        let session = try MoriRemoteTerminalSession(transport: recordingTransport(recorder))
        let start = Task { try await session.start() }

        start.cancel()
        do {
            try await start.value
            XCTFail("expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        let startCount = await recorder.startCount
        XCTAssertEqual(startCount, 0)
        await session.stop()
    }

    func testStopReleasesStartWaitingForInitialViewport() async throws {
        let recorder = FacadeStartRecorder()
        let session = try MoriRemoteTerminalSession(transport: recordingTransport(recorder))
        let start = Task { try await session.start() }

        await Task.yield()
        await session.stop()
        do {
            try await start.value
            XCTFail("expected stopped start to fail")
        } catch {
        }

        let startCount = await recorder.startCount
        XCTAssertEqual(startCount, 0)
    }

    func testFixedMetadataCommandUsesMoriHookOptionNames() {
        XCTAssertEqual(
            TmuxSessionController.agentMetadataQuery,
            "list-panes -a -f '#{&&:#{==:#{m/r:[[:cntrl:]],#{session_name}},0},#{&&:#{==:#{m/r:[[:cntrl:]],#{window_name}},0},#{&&:#{==:#{m/r:[[:cntrl:]],#{@mori-agent-state}},0},#{==:#{m/r:[[:cntrl:]],#{@mori-agent-name}},0}}}}' -F '#{q:session_name}|#{window_id}|#{q:window_name}|#{pane_id}|#{q:@mori-agent-state}|#{q:@mori-agent-name}'"
        )
    }

    private func failingTransport() -> MoriRemoteTerminalTransport {
        let stream = AsyncThrowingStream<Data, Error> { $0.finish() }
        return .init(
            receivedBytes: stream,
            start: { _ in throw FacadeFailure.synthetic },
            send: { _ in },
            close: { _ in },
            isActive: { false }
        )
    }

    private func inertTransport() -> MoriRemoteTerminalTransport {
        let stream = AsyncThrowingStream<Data, Error> { $0.finish() }
        return .init(
            receivedBytes: stream,
            start: { _ in },
            send: { _ in },
            close: { _ in },
            isActive: { false }
        )
    }

    private func recordingTransport(_ recorder: FacadeStartRecorder) -> MoriRemoteTerminalTransport {
        let stream = AsyncThrowingStream<Data, Error> { _ in }
        return .init(
            receivedBytes: stream,
            start: { await recorder.started(viewport: $0) },
            send: { _ in },
            close: { _ in },
            isActive: { false }
        )
    }
}

private actor FacadeStartRecorder {
    private(set) var startCount = 0

    func started(viewport _: TmuxControlViewport) {
        startCount += 1
    }
}

private enum FacadeFailure: LocalizedError {
    case synthetic
    var errorDescription: String? { "synthetic transport failure" }
}
