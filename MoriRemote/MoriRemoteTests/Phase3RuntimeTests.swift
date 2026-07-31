import Foundation
import Testing
@testable import MoriRemote

@Suite("Phase 3 Ghostty control boundaries") struct Phase3RuntimeTests {
    @Test("deterministic transport preserves delayed chunks and writes")
    func deterministicTranscript() async throws {
        let transport = DeterministicTmuxControlTransport(events: [.chunk("first"), .chunk("second", after: 1_000_000)])
        try await transport.start()
        var received: [Data] = []
        for try await chunk in transport.receivedBytes { received.append(chunk) }
        try await transport.send(Data("select-window -t @1\n".utf8))
        #expect(received == [Data("first".utf8), Data("second".utf8)])
        #expect(await transport.sentWrites() == [Data("select-window -t @1\n".utf8)])
    }

    @Test("deterministic transport exposes terminal errors")
    func deterministicError() async throws {
        enum Failure: Error { case expected }
        let transport = DeterministicTmuxControlTransport(events: [.chunk("prefix"), .failure(Failure.expected)])
        try await transport.start()
        var chunks = 0
        do { for try await _ in transport.receivedBytes { chunks += 1 }; Issue.record("expected failure") } catch { #expect(chunks == 1) }
    }

    @Test("link preserves controller batch admission order")
    func linkOrder() async throws {
        let transport = DeterministicTmuxControlTransport(transcript: [], holdOpen: true)
        let link = TmuxSessionLink(transport: transport, receive: { _ in }, disconnected: {})
        try await link.start(); link.enqueue(Data("first".utf8)); link.enqueue(Data("second".utf8))
        try await Task.sleep(for: .milliseconds(20))
        #expect(await transport.sentWrites() == [Data("first".utf8), Data("second".utf8)])
        await link.stop()
    }

    @Test("deterministic transport captures write failure")
    func deterministicWriteFailure() async throws {
        enum Failure: Error { case write }
        let transport = DeterministicTmuxControlTransport(transcript: [], writeError: Failure.write)
        do { try await transport.send(Data("x".utf8)); Issue.record("expected write failure") } catch {}
        #expect(await transport.sentWrites() == [Data("x".utf8)])
    }

    @Test("native controller parses the upstream startup transcript") @MainActor func nativeTranscript() async throws {
        let runtime = try GhosttyKitRuntime(); let observed = NativeObserver()
        let controller = TmuxSessionController(callbacks: .init(topology: { observed.topology($0) }, terminal: { observed.terminal($0) }))
        controller.setOutboundSink { observed.write($0) }
        try await withCheckedThrowingContinuation { continuation in controller.start(columns: 83, rows: 44) { continuation.resume(with: $0) } }
        let window = "$42 @0 1 %0 83 44 b7dd,83x44,0,0,0 b7dd,83x44,0,0,0 probe\n"
        let pane = "%0;83;44;0;0;1;;;;0;4294967295;4294967295;0;1;0;0;0;0;0;0;0;0;;;0;0;43;8,16\n"
        controller.pump(Data(("%begin 1 1 0\n%end 1 1 0\n%session-changed $42 main\n%begin 2 2 1\n3.1\n%end 2 2 1\n%begin 3 3 1\n%end 3 3 1\n%begin 4 4 1\n" + window + "%end 4 4 1\n%begin 5 5 1\n" + pane + "%end 5 5 1\n" + (6...9).map { "%begin \($0) \($0) 1\n%end \($0) \($0) 1\n" }.joined()).utf8))
        await drain(controller)
        #expect(observed.snapshot?.activePaneID == TmuxPaneID(0)); #expect(observed.snapshot?.activeWindowID == TmuxWindowID(0)); #expect(observed.terminals.contains(TmuxPaneID(0))); #expect(!observed.writes.isEmpty)
        await shutdown(controller); _ = runtime
    }

    @Test("local history ceilings are explicit") func historyCeilings() {
        #expect(TmuxSessionController.initialHistoryLineLimit == 2_000)
        #expect(TmuxSessionController.maximumScrollbackBytes == 2_560_000)
    }

    @Test("surface ledger rejects unknown and duplicate handles and fences removal")
    func surfaceLedger() {
        var ledger = TmuxSurfaceRegistrationLedger(); let pane = TmuxPaneID(7)
        #expect(ledger.register(paneID: pane, identity: 1, clientAvailable: true, retained: []) == .unknownPane)
        #expect(ledger.register(paneID: pane, identity: 1, clientAvailable: false, retained: [pane]) == .unavailable)
        #expect(ledger.register(paneID: pane, identity: 1, clientAvailable: true, retained: [pane]) == .registered)
        #expect(ledger.register(paneID: pane, identity: 2, clientAvailable: true, retained: [pane]) == .duplicate)
        #expect(ledger.unregister(paneID: pane, identity: 2) == .ignored)
        #expect(ledger.unregister(paneID: pane, identity: 1) == .removed)
        #expect(ledger.isEmpty)
    }

    @Test("topology projection retains active window and pane") func topologyProjection() {
        let window = TmuxSessionController.Window(id: .init(2), name: "work", active: true, activePaneID: .init(9))
        let topology = TmuxSessionController.Topology(revision: 4, sessionName: "main", windows: [window], panes: [.init(id: .init(9), windowID: .init(2), width: 80, height: 24, phase: .live)], activeWindowID: window.id)
        #expect(topology.revision == 4); #expect(topology.activePaneID == TmuxPaneID(9)); #expect(topology.panes[0].phase == .live)
    }

    @Test("runtime gate rejects stale and stopped callbacks") func runtimeGate() {
        let id = UUID(); var gate = GhosttyRuntimeCallbackGate(instanceID: id)
        #expect(gate.accepts(id)); #expect(!gate.accepts(UUID())); gate.stop(); #expect(!gate.accepts(id))
    }

    @Test("client-local selection commands never admit forbidden server mutations")
    func commandPolicy() {
        let window = TmuxClientCommandPolicy.selectWindow(.init(3)); let pane = TmuxClientCommandPolicy.selectPane(.init(4))
        #expect(window == "select-window -t @3"); #expect(pane == "select-pane -t %4")
        #expect(TmuxClientCommandPolicy.isAllowed(window)); #expect(TmuxClientCommandPolicy.isAllowed(pane))
        for forbidden in ["refresh-client -C 80x24", "resize-pane -Z -t %4", "copy-mode -t %4"] { #expect(!TmuxClientCommandPolicy.isAllowed(forbidden)) }
    }

    @Test("command result preserves success skipped error body and cause")
    func commandResults() {
        #expect(TmuxSessionController.CommandResult(status: .success, body: "ok", causeToken: 0).status == .success)
        let skipped = TmuxSessionController.CommandResult(status: .skipped, body: "", causeToken: 12)
        #expect(skipped.status == .skipped && skipped.causeToken == 12)
        #expect(TmuxSessionController.CommandResult(status: .error, body: "denied", causeToken: 1).body == "denied")
    }

    @Test("marked CJK text commits once and replaces intermediate composition")
    func markedText() {
        var composition = GhosttyMarkedTextComposition(); composition.update("ni"); composition.update("你")
        #expect(composition.isActive)
        #expect(composition.commit("") == "你"); #expect(composition.commit("") == nil)
    }

    @Test("text input shim exposes marked range and bounded virtual positions")
    @MainActor func textInputShim() {
        let responder = GhosttyTerminalResponderView()
        responder.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0))
        #expect(responder.markedTextRange != nil)
        let start = responder.beginningOfDocument
        #expect((responder.position(from: start, offset: 9) as? GhosttyVirtualTextPosition)?.offset == 1)
        responder.unmarkText()
        #expect(responder.markedTextRange == nil)
    }

    @Test("scroll projection preserves terminal follow-bottom and user offset")
    func scrollProjection() {
        let projection = GhosttyScrollProjection()
        #expect(projection.synchronize(currentOffset: 12, contentHeight: 300, viewportHeight: 100, followsBottom: true) == 200)
        #expect(projection.synchronize(currentOffset: 12, contentHeight: 300, viewportHeight: 100, followsBottom: false) == 12)
    }

    @Test("scroll budget bounds a burst and refills deterministically") func scrollBudget() {
        var budget = GhosttyScrollDeltaBudget(unitsPerSecond: 100, burstSeconds: 0.1)
        #expect(budget.clamp(99, now: 0) == 10); #expect(budget.clamp(-1, now: 0) == 0); #expect(budget.clamp(-8, now: 0.08) == -8)
    }

    @Test("hardware keys and Ctrl text map to terminal protocol") @MainActor func hardwareKeyMapping() {
        #expect(GhosttySurfaceKeyEvent.backspace.keyCode == 0x33); #expect(GhosttySurfaceKeyEvent.enter.keyCode == 0x24)
        #expect(GhosttySurfaceKeyEvent.home.keyCode == 0x73); #expect(GhosttySurfaceKeyEvent.pageDown.keyCode == 0x79)
        #expect(GhosttyTerminalHardwareCommandMapping.command(characters: "c", keyCode: .keyboardC, modifiers: .control) == .text("\u{03}"))
        #expect(GhosttyTerminalHardwareCommandMapping.command(characters: " ", keyCode: .keyboardSpacebar, modifiers: .control) == .text("\0"))
        #expect(GhosttyTerminalHardwareCommandMapping.command(characters: "\u{03}", keyCode: .keyboardC, modifiers: .control) == .text("\u{03}"))
    }


    private func drain(_ controller: TmuxSessionController) async { await withCheckedContinuation { continuation in controller.queue.async { continuation.resume() } } }
    private func shutdown(_ controller: TmuxSessionController) async { await withCheckedContinuation { continuation in controller.shutdown { continuation.resume() } } }
}

private final class NativeObserver: @unchecked Sendable { private let lock = NSLock(); private(set) var snapshot: TmuxSessionController.Topology?; private(set) var terminals: [TmuxPaneID] = []; private(set) var writes: [Data] = []; func topology(_ value: TmuxSessionController.Topology) { lock.withLock { snapshot = value } }; func terminal(_ value: TmuxSessionController.RetainedTerminal) { lock.withLock { terminals.append(value.paneID) } }; func write(_ value: Data) { lock.withLock { writes.append(value) } }
}
