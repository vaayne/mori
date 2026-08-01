import Foundation
import Testing
@testable import MoriRemote

@Suite("Agent metadata facade projection") struct Phase5AgentMetadataTests {
    @Test("parser strictly normalizes UInt64 pane IDs and bounds untrusted output")
    func parserNormalization() {
        let parser = AgentMetadataResponseParser()
        let metadata = parser.parse("%1\tworking\tclaude\n%2\tWAITING\tcodex\n%3\tdone\tpi\ninvalid\tworking\tbad\n%4\twaiting\tbad\u{0000}name\n")
        #expect(metadata[1] == .init(state: .working, name: "claude"))
        #expect(metadata[2] == .init(state: .unknown, name: "codex"))
        #expect(metadata[3] == .init(state: .done, name: "pi"))
        #expect(metadata[4] == .init(state: .waiting, name: nil))
        #expect(metadata[99] == nil)
        #expect(parser.parse(String(repeating: "x", count: AgentMetadataResponseParser.maximumResponseBytes + 1)).isEmpty)
    }

    @Test("injected valid pane rows and over-limit responses fail closed")
    func parserRejectsInjectionAndRecordOverflow() {
        let parser = AgentMetadataResponseParser()
        let injectedName = "claude\n%2\twaiting\tclaude"
        let response = "%1\tworking\t\(injectedName)\n%2\tdone\tpi\n"
        #expect(parser.parse(response).isEmpty)

        let overLimit = (0...AgentMetadataResponseParser.maximumRecords)
            .map { "%\($0)\tworking\tclaude\n" }
            .joined()
        #expect(parser.parse(overLimit).isEmpty)
    }

    @Test("authoritative merge clears missing records and ignores removed panes")
    func projectionMerge() {
        let records: [UInt64: AgentMetadata] = [
            1: .init(state: .working, name: "claude"),
            9: .init(state: .done, name: "other")
        ]
        let merged = AgentMetadataProjection.merge(records, paneIDs: [1, 2])
        #expect(merged == [
            1: .init(state: .working, name: "claude"),
            2: .unknown
        ])
    }

    @Test("duplicate facade topology panes are deterministically uniqued")
    func projectionDuplicateTopology() {
        let merged = AgentMetadataProjection.merge([1: .init(state: .done, name: "pi")], paneIDs: [1, 1, 2])
        #expect(merged == [1: .init(state: .done, name: "pi"), 2: .unknown])
    }

    @Test("visible projector consumes the facade's fixed success result") @MainActor
    func projectorRefreshesOptions() async {
        let relay = QueryRelay()
        let projector = AgentMetadataProjector(instanceID: UUID()) { await relay.query() }
        projector.topologyDidChange(paneIDs: [1])
        projector.setVisible(true)
        await relay.waitUntilRequested()

        relay.complete(.init(succeeded: true, body: "%1\tworking\tclaude\n"))
        await eventually { projector.metadata[1] == .init(state: .working, name: "claude") }
        #expect(projector.metadata[1] == .init(state: .working, name: "claude"))

        projector.foregrounded()
        await relay.waitUntilRequested()
        relay.complete(.init(succeeded: true, body: "%1\twaiting\tclaude\n"))
        await eventually { projector.metadata[1] == .init(state: .waiting, name: "claude") }
        #expect(projector.metadata[1] == .init(state: .waiting, name: "claude"))
        projector.stop()
    }

    @Test("failed query yields unknown and cancellation rejects a late response") @MainActor
    func queryFailureAndCancellation() async {
        let relay = QueryRelay()
        let projector = AgentMetadataProjector(instanceID: UUID()) { await relay.query() }
        projector.topologyDidChange(paneIDs: [1])
        projector.setVisible(true)
        await relay.waitUntilRequested()
        relay.complete(.init(succeeded: false, body: "transport closed"))
        await eventually { projector.lastFailure == "transport closed" }
        #expect(projector.metadata[1] == .unknown)
        #expect(projector.lastFailure == "transport closed")

        projector.foregrounded()
        await relay.waitUntilRequested()
        projector.stop()
        relay.complete(.init(succeeded: true, body: "%1\tworking\tlate\n"))
        await Task.yield()
        #expect(projector.metadata.isEmpty)
    }

    @Test("hiding clears badges and a late generation cannot repopulate them") @MainActor
    func hideReshowDropsLateResponse() async {
        let relay = QueryRelay()
        let projector = AgentMetadataProjector(instanceID: UUID()) { await relay.query() }
        projector.topologyDidChange(paneIDs: [1])
        projector.setVisible(true)
        await relay.waitUntilRequested()
        relay.complete(.init(succeeded: true, body: "%1\tworking\tclaude\n"))
        await eventually { projector.metadata[1] == .init(state: .working, name: "claude") }

        projector.foregrounded()
        await relay.waitUntilRequested()
        projector.setVisible(false)
        #expect(projector.metadata.isEmpty)
        projector.setVisible(true)
        await relay.waitUntilRequested()
        relay.complete(.init(succeeded: true, body: "%1\tdone\tlate\n"))
        await Task.yield()
        #expect(projector.metadata.isEmpty)
        relay.complete(.init(succeeded: true, body: "%1\twaiting\tclaude\n"))
        await eventually { projector.metadata[1] == .init(state: .waiting, name: "claude") }
        #expect(projector.metadata[1] == .init(state: .waiting, name: "claude"))
        projector.stop()
    }

    @Test("replaced runtime projector cannot publish an old facade response") @MainActor
    func runtimeReplacementFence() async {
        let oldRelay = QueryRelay()
        let old = AgentMetadataProjector(instanceID: UUID()) { await oldRelay.query() }
        old.topologyDidChange(paneIDs: [1])
        old.setVisible(true)
        await oldRelay.waitUntilRequested()
        old.stop()

        let newRelay = QueryRelay()
        let replacement = AgentMetadataProjector(instanceID: UUID()) { await newRelay.query() }
        replacement.topologyDidChange(paneIDs: [1])
        replacement.setVisible(true)
        await newRelay.waitUntilRequested()
        oldRelay.complete(.init(succeeded: true, body: "%1\tdone\told\n"))
        newRelay.complete(.init(succeeded: true, body: "%1\tworking\tnew\n"))
        await eventually { replacement.metadata[1] == .init(state: .working, name: "new") }
        #expect(old.metadata.isEmpty)
        #expect(replacement.metadata[1] == .init(state: .working, name: "new"))
        replacement.stop()
    }
}

@MainActor
private func eventually(_ condition: @escaping @MainActor () -> Bool) async {
    for _ in 0..<100 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("condition did not become true")
}

@MainActor
private final class QueryRelay {
    private var continuations: [CheckedContinuation<AgentMetadataQueryResult, Never>] = []
    private var requestedWaiters: [CheckedContinuation<Void, Never>] = []

    func query() async -> AgentMetadataQueryResult {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
            requestedWaiters.forEach { $0.resume() }
            requestedWaiters.removeAll()
        }
    }

    func waitUntilRequested() async {
        guard continuations.isEmpty else { return }
        await withCheckedContinuation { requestedWaiters.append($0) }
    }

    func complete(_ result: AgentMetadataQueryResult) {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume(returning: result)
    }
}
