import Foundation
import XCTest
@testable import MoriRemoteTerminal

@MainActor
final class MoriRemoteTerminalFacadeTests: XCTestCase {
    func testStartFailurePublishesDisconnectedStateAndError() async throws {
        let session = try MoriRemoteTerminalSession(transport: failingTransport())

        do {
            try await session.start()
            XCTFail("expected transport start failure")
        } catch {
            XCTAssertEqual(session.connectionState, .disconnected)
            XCTAssertEqual(session.lastError, "synthetic transport failure")
        }
        await session.stop()
    }

    func testStoppedSessionReturnsFixedFailedMetadataResult() async throws {
        let session = try MoriRemoteTerminalSession(transport: inertTransport())
        await session.stop()

        let result = await session.queryAgentMetadata()
        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.body, "")
    }

    func testFixedMetadataCommandUsesMoriHookOptionNames() {
        XCTAssertEqual(
            TmuxSessionController.agentMetadataQuery,
            "list-panes -a -F '#{pane_id}\\t#{@mori-agent-state}\\t#{@mori-agent-name}'"
        )
    }

    private func failingTransport() -> MoriRemoteTerminalTransport {
        let stream = AsyncThrowingStream<Data, Error> { $0.finish() }
        return .init(
            receivedBytes: stream,
            start: { throw FacadeFailure.synthetic },
            send: { _ in },
            close: { _ in },
            isActive: { false }
        )
    }

    private func inertTransport() -> MoriRemoteTerminalTransport {
        let stream = AsyncThrowingStream<Data, Error> { $0.finish() }
        return .init(
            receivedBytes: stream,
            start: {},
            send: { _ in },
            close: { _ in },
            isActive: { false }
        )
    }
}

private enum FacadeFailure: LocalizedError {
    case synthetic
    var errorDescription: String? { "synthetic transport failure" }
}
