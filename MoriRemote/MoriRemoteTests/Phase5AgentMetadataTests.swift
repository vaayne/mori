import Foundation
import Testing
@testable import MoriRemote

@Suite("Phase 5 agent metadata and adaptive presentation") struct Phase5AgentMetadataTests {
    @Test("parser strictly normalizes pane options and bounds untrusted output")
    func parserNormalization() {
        let parser = AgentMetadataResponseParser()
        let metadata = parser.parse("%1\tworking\tclaude\n%2\tWAITING\tcodex\n%3\tdone\tpi\ninvalid\tworking\tbad\n%4\twaiting\tbad\u{0000}name\n")
        #expect(metadata[.init(1)] == .init(state: .working, name: "claude"))
        #expect(metadata[.init(2)] == .init(state: .unknown, name: "codex"))
        #expect(metadata[.init(3)] == .init(state: .done, name: "pi"))
        #expect(metadata[.init(4)] == .init(state: .waiting, name: nil))
        #expect(metadata[.init(99)] == nil)
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
        let topology = makeTopology(paneIDs: [.init(1), .init(2)])
        let records: [TmuxPaneID: AgentMetadata] = [
            .init(1): .init(state: .working, name: "claude"),
            .init(9): .init(state: .done, name: "other")
        ]
        let merged = AgentMetadataProjection.merge(records, into: topology)
        #expect(merged == [
            .init(1): .init(state: .working, name: "claude"),
            .init(2): .unknown
        ])
    }

    @Test("duplicate topology panes are deterministically uniqued")
    func projectionDuplicateTopology() {
        let topology = makeTopology(paneIDs: [.init(1), .init(1), .init(2)])
        let merged = AgentMetadataProjection.merge([.init(1): .init(state: .done, name: "pi")], into: topology)
        #expect(merged == [.init(1): .init(state: .done, name: "pi"), .init(2): .unknown])
    }

    @Test("visible projector observes option changes without topology or terminal interruption") @MainActor
    func projectorRefreshesOptions() async {
        let relay = QueryRelay()
        let projector = AgentMetadataProjector(instanceID: UUID()) { relay.set($0) }
        projector.topologyDidChange(makeTopology(paneIDs: [.init(1)]))
        projector.setVisible(true)

        relay.complete(.success, "%1\tworking\tclaude\n")
        await Task.yield()
        #expect(projector.metadata[.init(1)] == .init(state: .working, name: "claude"))

        projector.foregrounded()
        relay.complete(.success, "%1\twaiting\tclaude\n")
        await Task.yield()
        #expect(projector.metadata[.init(1)] == .init(state: .waiting, name: "claude"))

        projector.foregrounded()
        relay.complete(.success, "%1\tdone\tclaude\n")
        await Task.yield()
        #expect(projector.metadata[.init(1)] == .init(state: .done, name: "claude"))
        projector.stop()
    }

    @Test("failed query yields unknown and cancellation rejects a late response") @MainActor
    func queryFailureAndCancellation() async {
        let relay = QueryRelay()
        let projector = AgentMetadataProjector(instanceID: UUID()) { relay.set($0) }
        projector.topologyDidChange(makeTopology(paneIDs: [.init(1)]))
        projector.setVisible(true)
        relay.complete(.error, "transport closed")
        await Task.yield()
        #expect(projector.metadata[.init(1)] == .unknown)
        #expect(projector.lastFailure == "transport closed")

        projector.foregrounded()
        projector.stop()
        relay.complete(.success, "%1\tworking\tlate\n")
        await Task.yield()
        #expect(projector.metadata.isEmpty)
    }

    @Test("hiding clears badges and a late generation cannot repopulate them") @MainActor
    func hideReshowDropsLateResponse() async {
        let relay = QueryRelay()
        let projector = AgentMetadataProjector(instanceID: UUID()) { relay.set($0) }
        var changes = 0
        projector.onChange = { changes += 1 }
        projector.topologyDidChange(makeTopology(paneIDs: [.init(1)]))
        projector.setVisible(true)
        relay.complete(.success, "%1\tworking\tclaude\n")
        await Task.yield()
        #expect(projector.metadata[.init(1)]?.state == .working)

        projector.foregrounded() // leave this generation in flight
        projector.setVisible(false)
        #expect(projector.metadata.isEmpty)
        #expect(changes >= 3)
        projector.setVisible(true)
        relay.complete(.success, "%1\tdone\tlate\n")
        await Task.yield()
        #expect(projector.metadata.isEmpty)
        relay.complete(.success, "%1\twaiting\tclaude\n")
        await Task.yield()
        #expect(projector.metadata[.init(1)] == .init(state: .waiting, name: "claude"))
        projector.stop()
    }

    @Test("replaced runtime projector cannot publish an old response") @MainActor
    func runtimeReplacementFence() async {
        let oldRelay = QueryRelay()
        let old = AgentMetadataProjector(instanceID: UUID()) { oldRelay.set($0) }
        old.topologyDidChange(makeTopology(paneIDs: [.init(1)]))
        old.setVisible(true)
        old.stop()

        let newRelay = QueryRelay()
        let replacement = AgentMetadataProjector(instanceID: UUID()) { newRelay.set($0) }
        replacement.topologyDidChange(makeTopology(paneIDs: [.init(1)]))
        replacement.setVisible(true)
        oldRelay.complete(.success, "%1\tdone\told\n")
        newRelay.complete(.success, "%1\tworking\tnew\n")
        await Task.yield()
        #expect(old.metadata.isEmpty)
        #expect(replacement.metadata[.init(1)] == .init(state: .working, name: "new"))
        replacement.stop()
    }

    @Test("fixed metadata command stays inside the sole controller admission boundary")
    func metadataQueryPolicy() {
        #expect(TmuxClientCommandPolicy.isAllowed(TmuxClientCommandPolicy.agentMetadataQuery))
        #expect(!TmuxClientCommandPolicy.isAllowed("list-panes -a"))
        #expect(!TmuxClientCommandPolicy.isAllowed("set-option -p @mori-agent-state working"))
        #expect(!TmuxClientCommandPolicy.agentMetadataQuery.contains("refresh-client"))
    }

    @Test("compact and regular presentation preserve terminal runtime identity")
    func presentationIdentity() {
        let instance = UUID()
        #expect(RemoteTerminalPresentation.identity(for: instance, mode: .compact) == instance)
        #expect(RemoteTerminalPresentation.identity(for: instance, mode: .regular) == instance)
        #expect(RemoteTerminalPresentation.identity(for: UUID(), mode: .regular) != instance)
    }

    private func makeTopology(paneIDs: [TmuxPaneID]) -> TmuxSessionController.Topology {
        let window = TmuxSessionController.Window(id: .init(1), name: "build", active: true, activePaneID: paneIDs.first ?? .init(0))
        let panes = paneIDs.map { TmuxSessionController.Pane(id: $0, windowID: window.id, width: 80, height: 24, phase: .live) }
        return .init(revision: 1, sessionName: "workspace", windows: [window], panes: panes, activeWindowID: window.id)
    }
}

private final class QueryRelay: @unchecked Sendable {
    private var completions: [@Sendable (TmuxSessionController.CommandResult) -> Void] = []
    func set(_ completion: @escaping @Sendable (TmuxSessionController.CommandResult) -> Void) { completions.append(completion) }
    func complete(_ status: TmuxSessionController.CommandStatus, _ body: String) {
        guard !completions.isEmpty else { return }
        completions.removeFirst()(.init(status: status, body: body, causeToken: 1))
    }
}
