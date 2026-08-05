import Foundation
import Testing
@testable import MoriRemote

@Suite("Agent metadata facade projection") struct Phase5AgentMetadataTests {
    @Test("parser retains host context and strictly normalizes untrusted output")
    func parserNormalization() {
        let parser = AgentMetadataResponseParser()
        let records = parser.parse("main|@1|editor|%1|working|claude\nmain|@2|deploy|%2|WAITING|codex\n")
        #expect(records == [
            target(session: "main", windowID: 1, windowTitle: "editor", paneID: 1, state: .working, name: "claude"),
            target(session: "main", windowID: 2, windowTitle: "deploy", paneID: 2, state: .unknown, name: "codex")
        ])
        #expect(parser.parse(String(repeating: "x", count: AgentMetadataResponseParser.maximumResponseBytes + 1)).isEmpty)
    }

    @Test("malformed, injected, and duplicate source records fail closed while shadows stay hidden")
    func parserRejectsInjectionAndRecordOverflow() {
        let parser = AgentMetadataResponseParser()
        let injectedName = "claude\nmain|@2|deploy|%2|waiting|claude"
        let response = "main|@1|editor|%1|working|\(injectedName)\nmain|@2|deploy|%2|done|pi\n"
        #expect(parser.parse(response).isEmpty)

        #expect(parser.parse("main|bad|editor|%1|working|claude\n").isEmpty)
        #expect(parser.parse("main|@1|editor|%1|working|claude\nmain|@1|editor|%1|done|pi\n").isEmpty)
        #expect(parser.parse("main|@1|editor|title|%1|working|claude\n").isEmpty)

        let shadowID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let shadow = "main--mori-remote-\(shadowID.uuidString.lowercased())"
        #expect(parser.parse("\(shadow)|@1|editor|%1|working|claude\nmain|@1|editor|%1|waiting|pi\n") == [
            target(session: "main", windowID: 1, windowTitle: "editor", paneID: 1, state: .waiting, name: "pi")
        ])

        let overLimit = (0...AgentMetadataResponseParser.maximumRecords)
            .map { "main|@1|editor|%\($0)|working|claude\n" }
            .joined()
        #expect(parser.parse(overLimit).isEmpty)
    }

    @Test("host-wide attention is ordered and summarized before local projection")
    func projectionMerge() {
        let records = [
            target(session: "zeta", windowID: 2, windowTitle: "deploy", paneID: 9, state: .done, name: "other"),
            target(session: "main", windowID: 1, windowTitle: "editor", paneID: 1, state: .working, name: "claude"),
            target(session: "main", windowID: 3, windowTitle: "review", paneID: 3, state: .waiting, name: "pi")
        ]
        let merged = AgentMetadataProjection.merge(records, paneIDs: [1, 2])
        #expect(merged == [
            1: .init(state: .working, name: "claude"),
            2: .unknown
        ])
        #expect(AgentAttentionProjection.ordered(records).map(\.paneID) == [3, 1, 9])
        #expect(AgentAttentionProjection.summary(records) == .init(waiting: 1, working: 1, done: 1))
    }

    @Test("duplicate facade topology panes are deterministically uniqued")
    func projectionDuplicateTopology() {
        let merged = AgentMetadataProjection.merge([
            target(session: "main", windowID: 1, windowTitle: "editor", paneID: 1, state: .done, name: "pi")
        ], paneIDs: [1, 1, 2])
        #expect(merged == [1: .init(state: .done, name: "pi"), 2: .unknown])
    }

    @Test("visible projector consumes the facade's fixed success result") @MainActor
    func projectorRefreshesOptions() async {
        let relay = QueryRelay()
        let projector = AgentMetadataProjector(instanceID: UUID()) { await relay.query() }
        projector.topologyDidChange(paneIDs: [1])
        projector.setVisible(true)
        await relay.waitUntilRequested()

        relay.complete(.init(succeeded: true, body: "main|@1|editor|%1|working|claude\n"))
        await eventually { projector.metadata[1] == .init(state: .working, name: "claude") }
        #expect(projector.metadata[1] == .init(state: .working, name: "claude"))

        projector.foregrounded()
        await relay.waitUntilRequested()
        relay.complete(.init(succeeded: true, body: "main|@1|editor|%1|waiting|claude\n"))
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
        relay.complete(.init(succeeded: true, body: "main|@1|editor|%1|working|late\n"))
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
        relay.complete(.init(succeeded: true, body: "main|@1|editor|%1|working|claude\n"))
        await eventually { projector.metadata[1] == .init(state: .working, name: "claude") }

        projector.foregrounded()
        await relay.waitUntilRequested()
        projector.setVisible(false)
        #expect(projector.metadata.isEmpty)
        projector.setVisible(true)
        await relay.waitUntilRequested()
        relay.complete(.init(succeeded: true, body: "main|@1|editor|%1|done|late\n"))
        await Task.yield()
        #expect(projector.metadata.isEmpty)
        relay.complete(.init(succeeded: true, body: "main|@1|editor|%1|waiting|claude\n"))
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
        oldRelay.complete(.init(succeeded: true, body: "main|@1|editor|%1|done|old\n"))
        newRelay.complete(.init(succeeded: true, body: "main|@1|editor|%1|working|new\n"))
        await eventually { replacement.metadata[1] == .init(state: .working, name: "new") }
        #expect(old.metadata.isEmpty)
        #expect(replacement.metadata[1] == .init(state: .working, name: "new"))
        replacement.stop()
    }
}

private func target(
    session: String,
    windowID: UInt64,
    windowTitle: String,
    paneID: UInt64,
    state: MoriAgentState,
    name: String?
) -> AgentAttentionTarget {
    .init(
        sessionName: session,
        windowID: windowID,
        windowTitle: windowTitle,
        paneID: paneID,
        metadata: .init(state: state, name: name)
    )
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
