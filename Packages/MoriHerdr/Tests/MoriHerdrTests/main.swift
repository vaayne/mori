import Foundation
import MoriHerdr

// Same shape as the other test targets: plain functions, no XCTest, `runAsync` pumps the
// main RunLoop so Network framework callbacks land while an async test is in flight.

nonisolated(unsafe) var asyncDone = false

func runAsync(_ block: @escaping @Sendable () async -> Void) {
    asyncDone = false
    Task { await block(); asyncDone = true }
    while !asyncDone {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }
}

// MARK: - Socket path resolution

func testSocketPathResolution() {
    assertEqual(
        HerdrSocketPath.resolve(session: "default", home: "/home/x"),
        "/home/x/.config/herdr/herdr.sock",
        "the default session lives at the config root"
    )
    assertEqual(
        HerdrSocketPath.resolve(session: "mori", home: "/home/x"),
        "/home/x/.config/herdr/sessions/mori/herdr.sock",
        "named sessions get their own directory"
    )
    assertEqual(
        HerdrSocketPath.fromEnvironment(["HERDR_SOCKET_PATH": "/tmp/explicit.sock", "HERDR_SESSION": "mori"]),
        "/tmp/explicit.sock",
        "an explicit socket path wins over the session name"
    )
    assertNil(HerdrSocketPath.fromEnvironment([:]), "outside a herdr pane there is nothing to infer")
}

// MARK: - Event decoding

func decodeEvent(_ json: String) -> HerdrEvent? {
    HerdrEvent.decode(line: Data(json.utf8))
}

func testEventDecoding() {
    let focused = decodeEvent(#"{"event":"workspace_focused","data":{"type":"workspace_focused","workspace_id":"w2"}}"#)
    if case .workspaceFocused(let id) = focused {
        assertEqual(id, "w2")
    } else {
        assertTrue(false, "expected workspaceFocused, got \(String(describing: focused))")
    }

    let created = decodeEvent(#"""
    {"event":"pane_created","data":{"type":"pane_created","pane":{"pane_id":"w1:p1","terminal_id":"term_1","workspace_id":"w1","tab_id":"w1:t1","focused":true,"cwd":"/tmp","foreground_cwd":"/tmp","agent_status":"unknown","revision":0}}}
    """#)
    if case .paneCreated(let pane) = created {
        assertEqual(pane.paneID, "w1:p1")
        assertEqual(pane.terminalID, "term_1")
        assertEqual(pane.agentStatus, .unknown)
    } else {
        assertTrue(false, "expected paneCreated, got \(String(describing: created))")
    }

    let status = decodeEvent(#"{"event":"pane_agent_status_changed","data":{"type":"pane_agent_status_changed","pane_id":"w1:p1","agent_status":"working","agent":"claude"}}"#)
    if case .paneAgentStatusChanged(let pane, let state, let agent) = status {
        assertEqual(pane, "w1:p1")
        assertEqual(state, .working)
        assertEqual(agent, "claude")
    } else {
        assertTrue(false, "expected paneAgentStatusChanged, got \(String(describing: status))")
    }

    // Regression: herdr sends this one event under its dotted method name while every
    // other event is snake_cased, and omits `data.type`. Both spellings must decode.
    let dotted = decodeEvent(#"{"event":"pane.agent_status_changed","data":{"pane_id":"w1:p1","agent_status":"blocked","agent":"claude","workspace_id":"w1"}}"#)
    if case .paneAgentStatusChanged(let pane, let state, _) = dotted {
        assertEqual(pane, "w1:p1")
        assertEqual(state, .blocked)
    } else {
        assertTrue(false, "expected paneAgentStatusChanged from the dotted name, got \(String(describing: dotted))")
    }

    // A newer herdr must widen the stream, not break it.
    let future = decodeEvent(#"{"event":"quantum_entangled","data":{"type":"quantum_entangled","spooky":true}}"#)
    if case .other(let name, _) = future {
        assertEqual(name, "quantum_entangled", "unknown events survive as .other")
    } else {
        assertTrue(false, "expected .other, got \(String(describing: future))")
    }

    assertNil(decodeEvent(#"{"id":"sub1","result":{"type":"subscription_started"}}"#), "acks are not events")
    assertNil(decodeEvent("not json"), "garbage is not an event")
}

func testReportedStateMapsMoriVocabulary() {
    assertEqual(HerdrReportedAgentState.fromMoriState("waiting"), .blocked, "Mori says waiting, herdr says blocked")
    assertEqual(HerdrReportedAgentState.fromMoriState("working"), .working)
    assertEqual(HerdrReportedAgentState.fromMoriState("nonsense"), .unknown)
    // `done` is derived by herdr and rejected on report, so it has no reportable spelling.
    assertNil(HerdrReportedAgentState(rawValue: "done"), "done is not a state a client may report")
    assertEqual(HerdrReportedAgentState.blocked.status, HerdrAgentStatus.blocked)
}

func testAgentStatusToleratesUnknownStates() {
    struct Holder: Decodable { let agentStatus: HerdrAgentStatus }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let holder = try? decoder.decode(Holder.self, from: Data(#"{"agent_status":"transcending"}"#.utf8))
    assertEqual(holder?.agentStatus, .unknown, "a state from a newer herdr degrades instead of failing")
}

func testModelsIgnoreUnknownFields() {
    let json = #"""
    {"workspace_id":"w1","number":1,"label":"mori::demo","focused":true,"pane_count":2,
     "tab_count":1,"active_tab_id":"w1:t1","agent_status":"working","some_future_field":42}
    """#
    let workspace = try? JSONDecoder().decode(HerdrWorkspace.self, from: Data(json.utf8))
    assertEqual(workspace?.workspaceID, "w1")
    assertEqual(workspace?.label, "mori::demo")
    assertEqual(workspace?.agentStatus, .working)
    assertEqual(workspace?.paneCount, 2)
}

func testJSONValueRoundTrip() {
    let value = JSONValue.object([
        "cwd": "/tmp",
        "focus": true,
        "count": 3,
        "nested": .array([.string("a"), .null]),
    ])
    guard let encoded = try? JSONEncoder().encode(value),
          let decoded = try? JSONDecoder().decode(JSONValue.self, from: encoded)
    else {
        assertTrue(false, "JSONValue failed to round-trip")
        return
    }
    assertEqual(decoded, value)
    assertEqual(decoded["count"]?.intValue, 3, "integers stay integers rather than becoming 3.0")
    assertEqual(decoded["cwd"]?.stringValue, "/tmp")
}

// MARK: - Failure modes that need no server

func testUnreachableSocketFailsFast() {
    runAsync {
        let backend = HerdrBackend(socketPath: "/tmp/mori-herdr-does-not-exist.sock", timeout: 2)
        let started = Date()
        let reachable = await backend.isReachable()
        assertFalse(reachable, "there is no server at that path")
        assertTrue(Date().timeIntervalSince(started) < 5, "it fails fast instead of hanging")
    }
}

// MARK: - Tests against a real server

func testHandshakeAndSnapshot(_ backend: HerdrBackend) async {
    do {
        let info = try await backend.handshake()
        assertTrue(info.protocol >= HerdrBackend.minimumProtocol, "server protocol \(info.protocol) is supported")

        // Two calls in a row: herdr closes the socket after answering, so this is the
        // regression test for the one-request-per-connection design.
        let snapshot = try await backend.snapshot()
        assertEqual(snapshot.protocol, info.protocol, "a second call on the same client works")
        assertEqual(snapshot.version, info.version)
        // A headless server starts with nothing: no workspace exists until something asks
        // for one. Mori therefore cannot assume a pane is there to attach to on boot.
        assertEqual(snapshot.workspaces.count, 0, "a fresh server has an empty tree")
        assertNil(snapshot.focusedWorkspaceID, "nothing is focused before a workspace exists")
    } catch {
        assertTrue(false, "handshake/snapshot failed: \(error)")
    }
}

func testWorkspaceLifecycle(_ backend: HerdrBackend) async {
    do {
        let label = "mori::test-lifecycle"
        let created = try await backend.createWorkspace(cwd: NSTemporaryDirectory(), label: label, focus: true)
        assertEqual(created.workspace.label, label)
        assertEqual(created.rootPane.workspaceID, created.workspace.workspaceID)

        let found = try await backend.workspace(labeled: label)
        assertEqual(found?.workspaceID, created.workspace.workspaceID, "labels are how Mori resolves identity")

        try await backend.focusWorkspace(id: created.workspace.workspaceID)
        let snapshot = try await backend.snapshot()
        assertEqual(snapshot.focusedWorkspaceID, created.workspace.workspaceID, "focus lives on the server")

        try await backend.closeWorkspace(id: created.workspace.workspaceID)
        let afterClose = try await backend.workspace(labeled: label)
        assertNil(afterClose, "a closed workspace is gone from the list")
    } catch {
        assertTrue(false, "workspace lifecycle failed: \(error)")
    }
}

func testServerErrorsSurface(_ backend: HerdrBackend) async {
    do {
        try await backend.focusWorkspace(id: "no-such-workspace")
        assertTrue(false, "focusing a missing workspace should fail")
    } catch let error as HerdrError {
        assertEqual(error.serverCode, "workspace_not_found", "the server's error code reaches the caller")
    } catch {
        assertTrue(false, "expected a HerdrError, got \(error)")
    }
}

func testSubscriptionReceivesPushedEvent(_ backend: HerdrBackend) async {
    let stream = backend.eventStream(subscriptions: [.workspaceCreated, .workspaceClosed, .paneCreated])
    let collector = EventCollector()
    await collector.attach(await stream.start())

    let connected = await collector.first(matching: { $0.isConnected })
    assertNotNil(connected, "the subscription is acknowledged")

    // herdr replays existing state on subscribe, so a pushed event has to be told apart
    // from the replay — the label makes that unambiguous.
    let label = "mori::test-push"
    var createdID: String?
    do {
        createdID = try await backend.createWorkspace(cwd: NSTemporaryDirectory(), label: label, focus: false)
            .workspace.workspaceID
    } catch {
        assertTrue(false, "could not create the workspace to observe: \(error)")
    }

    let pushed = await collector.first(matching: { element in
        guard case .workspaceCreated(let workspace) = element.event else { return false }
        return workspace.label == label
    })
    assertNotNil(pushed, "the created workspace arrived over the subscription")

    if let createdID {
        try? await backend.closeWorkspace(id: createdID)
    }
    await stream.stop()
    await collector.detach()
}

func testSubscriptionReplaysStateOnConnect(_ backend: HerdrBackend) async {
    let label = "mori::test-replay"
    guard let created = try? await backend.createWorkspace(cwd: NSTemporaryDirectory(), label: label, focus: false) else {
        assertTrue(false, "could not create the workspace to replay")
        return
    }

    // Subscribing *after* the workspace exists: if herdr only sent deltas, nothing would arrive.
    let stream = backend.eventStream(subscriptions: [.workspaceCreated])
    let collector = EventCollector()
    await collector.attach(await stream.start())

    let replayed = await collector.first(matching: { element in
        guard case .workspaceCreated(let workspace) = element.event else { return false }
        return workspace.label == label
    })
    assertNotNil(replayed, "subscribing replays current state, which is what makes re-subscribe safe")

    await stream.stop()
    await collector.detach()
    try? await backend.closeWorkspace(id: created.workspace.workspaceID)
}

func testPerPaneAgentSubscription(_ backend: HerdrBackend) async {
    guard let created = try? await backend.createWorkspace(
        cwd: NSTemporaryDirectory(), label: "mori::test-agent", focus: false
    ) else {
        assertTrue(false, "could not create the workspace to watch")
        return
    }
    let paneID = created.rootPane.paneID

    let stream = backend.eventStream(subscriptions: [.paneCreated])
    let collector = EventCollector()
    await collector.attach(await stream.start())
    assertNotNil(await collector.first(matching: { $0.isConnected }), "base subscription connected")

    // Widening the watch set re-subscribes; agent status has no wildcard subscription.
    await stream.setWatchedPanes([paneID])
    await collector.clear()
    assertNotNil(await collector.first(matching: { $0.isConnected }), "re-subscribed with the pane added")

    do {
        try await backend.reportAgent(paneID: paneID, source: "mori", agent: "claude", state: .working)
    } catch {
        assertTrue(false, "report_agent failed: \(error)")
    }

    let status = await collector.first(matching: { element in
        guard case .paneAgentStatusChanged(let pane, let state, _) = element.event else { return false }
        return pane == paneID && state == .working
    })
    assertNotNil(status, "the agent status Mori reported came back over the subscription")

    if let agent = try? await backend.agents().first(where: { $0.paneID == paneID }) {
        assertEqual(agent.agent, "claude")
        assertEqual(agent.agentStatus, .working, "agent.list agrees with the pushed event")
    } else {
        assertTrue(false, "agent.list did not report the pane")
    }

    await stream.stop()
    await collector.detach()
    try? await backend.closeWorkspace(id: created.workspace.workspaceID)
}

func testInvalidSubscriptionIsReportedNotSwallowed(_ backend: HerdrBackend, _ subscription: HerdrSubscription, _ label: String) async {
    // herdr validates the subscription list as a whole and rejects it by answering under an
    // empty id and closing the socket. The stream must surface that instead of hanging.
    let stream = backend.eventStream(subscriptions: [subscription])
    let collector = EventCollector()
    await collector.attach(await stream.start())

    let failure = await collector.first(matching: { $0.disconnectReason != nil }, within: 8)
    assertNotNil(failure, "\(label): a rejected subscription reports a disconnect rather than hanging")
    if let reason = failure?.disconnectReason {
        assertTrue(reason.contains("invalid_request"), "\(label): the reason carries the server's code, got: \(reason)")
    }
    assertFalse(
        await collector.all().contains(where: { $0.isConnected }),
        "\(label): a rejected subscription never reports as connected"
    )

    await stream.stop()
    await collector.detach()
}

// MARK: - Run

testSocketPathResolution()
testEventDecoding()
testAgentStatusToleratesUnknownStates()
testReportedStateMapsMoriVocabulary()
testModelsIgnoreUnknownFields()
testJSONValueRoundTrip()
testUnreachableSocketFailsFast()
testConfigRendersTheKeysHerdrActuallyAccepts()
testConfigWriterOnlyRewritesOnChange()
testEnvironmentBindsProcessesToMorisSession()
runAsync { await testControllerReportsAMissingBinary() }

do {
    let server = try HerdrTestServer()
    try server.start()
    print("  herdr test server on \(server.socketPath)")
    let backend = HerdrBackend(socketPath: server.socketPath)

    runAsync {
        await testHandshakeAndSnapshot(backend)
        await testWorkspaceLifecycle(backend)
        await testServerErrorsSurface(backend)
        await testSubscriptionReceivesPushedEvent(backend)
        await testSubscriptionReplaysStateOnConnect(backend)
        await testPerPaneAgentSubscription(backend)
        await testInvalidSubscriptionIsReportedNotSwallowed(
            backend, HerdrSubscription(type: "workspace.list_changed"), "unknown event name"
        )
        // The specific trap this package exists to hide: agent status has no wildcard.
        await testInvalidSubscriptionIsReportedNotSwallowed(
            backend, HerdrSubscription(type: "pane.agent_status_changed"), "agent status without a pane"
        )
    }

    let herdrBinary = server.binaryPath
    runAsync {
        await testControllerStartsAndRestartsTheServer(herdrBinary)
    }

    server.stop()
} catch {
    failCount += 1
    print("  FAIL could not run the server-backed tests: \(error)")
}

printResults()

if failCount > 0 {
    fflush(stdout)
    fatalError("Tests failed")
}
