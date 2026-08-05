import Foundation
import XCTest
@testable import MoriRemoteTerminal

@MainActor
final class MoriTmuxNativeStartupIsolationTests: XCTestCase {
    func testSizedNativeStartupBootstrapsWithRefreshClient() async throws {
        // GhosttyKitRuntime must outlive the native client: it owns Ghostty's
        // initialized backend and app for this production-equivalent harness.
        let runtime = try GhosttyKitRuntime()
        withExtendedLifetime(runtime) {}
        let writes = LockedWrites()
        let controller = TmuxSessionController(callbacks: .init())
        controller.setOutboundSink { writes.append($0) }

        try await withCheckedThrowingContinuation { continuation in
            controller.start(initialSize: .init(cols: 83, rows: 44)) { continuation.resume(with: $0) }
        }
        controller.pump(Data("%begin 1 1 0\n%end 1 1 0\n%session-changed $42 main\n".utf8))
        try await Task.sleep(for: .milliseconds(50))

        let outbound = writes.text
        XCTAssertTrue(outbound.contains("version"), outbound)
        XCTAssertTrue(outbound.contains("list-windows"), outbound)
        XCTAssertTrue(outbound.contains("refresh-client -C 83x44"), outbound)
        await withCheckedContinuation { continuation in controller.shutdown { continuation.resume() } }
    }

    func testChangedClientSizeEmitsOneExactRefreshAndInvalidSizeFails() async throws {
        let runtime = try GhosttyKitRuntime()
        let writes = LockedWrites()
        let failures = RequestRecorder()
        let controller = TmuxSessionController(callbacks: .init(
            onRequestFailed: { failures.append($0) }
        ))
        controller.setOutboundSink { writes.append($0) }
        try await withCheckedThrowingContinuation { continuation in
            controller.start(initialSize: .init(cols: 83, rows: 44)) { continuation.resume(with: $0) }
        }
        controller.pump(Data("%begin 1 1 0\n%end 1 1 0\n%session-changed $42 main\n".utf8))
        try await Task.sleep(for: .milliseconds(50))
        writes.reset()
        controller.setClientSize(cols: 100, rows: 40)
        controller.setClientSize(cols: 100, rows: 40)
        try await Task.sleep(for: .milliseconds(50))
        let outbound = writes.text
        XCTAssertEqual(outbound.components(separatedBy: "refresh-client -C 100x40").count - 1, 1, outbound)
        controller.setClientSize(cols: 0, rows: 40)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(failures.values, [.setClientSize])
        await withCheckedContinuation { continuation in controller.shutdown { continuation.resume() } }
        withExtendedLifetime(runtime) {}
    }

    func testInputCancelsStaleModeBeforePaneInputOutbound() async throws {
        let runtime = try GhosttyKitRuntime()
        let writes = LockedWrites()
        let controller = TmuxSessionController(callbacks: .init())
        controller.setOutboundSink { writes.append($0) }
        try await withCheckedThrowingContinuation { continuation in
            controller.start(initialSize: .init(cols: 83, rows: 44)) { continuation.resume(with: $0) }
        }
        controller.pump(Data("%begin 1 1 0\n%end 1 1 0\n%session-changed $42 main\n".utf8))
        try await Task.sleep(for: .milliseconds(50))
        controller.pump(Data("%begin 2 2 1\n3.1\n%end 2 2 1\n%begin 3 3 1\n%end 3 3 1\n%begin 4 4 1\n$42 @0 1 %0 83 44 b7dd,83x44,0,0,0 b7dd,83x44,0,0,0 shell\n%end 4 4 1\n".utf8))
        controller.pump(Data("%begin 5 5 1\n%end 5 5 1\n%begin 6 6 1\n%end 6 6 1\n%begin 7 7 1\n%end 7 7 1\n%begin 8 8 1\n%end 8 8 1\n%begin 9 9 1\n%end 9 9 1\n".utf8))
        try await Task.sleep(for: .milliseconds(50))

        writes.reset()
        controller.setClientSize(cols: 83, rows: 44)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(writes.text, "", "the already-submitted initial grid must be a no-op")

        writes.reset()
        XCTAssertTrue(controller.sendInput(paneID: 0, Data("ls\n".utf8)))
        try await Task.sleep(for: .milliseconds(50))
        let outbound = writes.text
        guard let cancel = outbound.range(of: "pane_in_mode"),
              let input = outbound.range(of: "send-keys -H -t %0") else {
            XCTFail("expected cancellation and pane input: \(outbound)")
            await withCheckedContinuation { continuation in controller.shutdown { continuation.resume() } }
            withExtendedLifetime(runtime) {}
            return
        }
        XCTAssertLessThan(cancel.lowerBound, input.lowerBound, outbound)

        writes.reset()
        controller.setClientSize(cols: 100, rows: 40)
        try await Task.sleep(for: .milliseconds(50))
        let resize = writes.text
        XCTAssertEqual(resize, "refresh-client -C 100x40\n")

        await withCheckedContinuation { continuation in controller.shutdown { continuation.resume() } }
        withExtendedLifetime(runtime) {}
    }
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [TmuxSessionController.Request] = []

    func append(_ request: TmuxSessionController.Request) {
        lock.lock()
        defer { lock.unlock() }
        requests.append(request)
    }

    var values: [TmuxSessionController.Request] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }
}

private final class LockedWrites: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Data] = []
    func append(_ value: Data) { lock.lock(); defer { lock.unlock() }; values.append(value) }
    var text: String { lock.lock(); defer { lock.unlock() }; return String(decoding: values.joined(), as: UTF8.self) }
    func reset() { lock.lock(); defer { lock.unlock() }; values.removeAll() }
}
