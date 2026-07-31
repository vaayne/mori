import Foundation
import GhosttyKit
import UIKit

/// Pure callback identity fence; native surfaces are deliberately not fabricated
/// in tests. Runtime callbacks may publish only while their original instance is live.
struct GhosttyRuntimeCallbackGate: Sendable {
    let instanceID: UUID
    private(set) var stopped = false
    mutating func stop() { stopped = true }
    func accepts(_ id: UUID) -> Bool { !stopped && id == instanceID }
}

/// One-shot composition. Native parsing stays on the controller queue; UIKit
/// owns renderers and waits for unregister before releasing their handles.
@MainActor
final class GhosttyTmuxRuntime {
    let instanceID: UUID
    private let app: ghostty_app_t
    private let controller: TmuxSessionController
    private let link: TmuxSessionLink
    private var surfaces: [TmuxPaneID: TmuxPaneSurface] = [:]
    private var gate: GhosttyRuntimeCallbackGate
    private var stopped: Bool { gate.stopped }
    private var viewport = CGSize(width: 390, height: 600)
    private var creatingPaneIDs = Set<TmuxPaneID>()
    private var creationWaiters: [CheckedContinuation<Void, Never>] = []

    var onTopology: (@MainActor (TmuxSessionController.Topology) -> Void)?
    var onSurface: (@MainActor (TmuxPaneSurface?) -> Void)?
    var onState: (@MainActor (TmuxSessionController.State) -> Void)?
    /// Phase 4 presents this server-side pane-input rejection; Phase 3 keeps
    /// it observable instead of silently dropping the controller callback.
    var onInputFailed: (@MainActor (String) -> Void)?

    init(app: ghostty_app_t, transport: any TmuxControlTransport, instanceID: UUID = UUID()) {
        self.app = app
        self.instanceID = instanceID
        gate = GhosttyRuntimeCallbackGate(instanceID: instanceID)
        let relay = Relay()
        controller = TmuxSessionController(callbacks: .init(
            state: { state in Task { @MainActor in relay.owner?.receive(state, from: relay.id) } },
            topology: { topology in Task { @MainActor in relay.owner?.receive(topology, from: relay.id) } },
            terminal: { terminal in Task { @MainActor in relay.owner?.receive(terminal, from: relay.id) } },
            paneRemoved: { paneID in Task { @MainActor in relay.owner?.remove(paneID, from: relay.id) } },
            inputFailed: { message in Task { @MainActor in relay.owner?.receiveInputFailure(message, from: relay.id) } }
        ))
        link = TmuxSessionLink(transport: transport, receive: { relay.controller?.pump($0) }, disconnected: { relay.controller?.transportClosed() })
        relay.controller = controller; relay.owner = self; relay.id = instanceID
        controller.setOutboundSink { [link] bytes in link.enqueue(bytes) }
    }

    func start(columns: UInt16, rows: UInt16, historyLineLimit: Int = TmuxSessionController.initialHistoryLineLimit) async throws {
        let controller = controller
        try await link.start(beforeReceive: { try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in controller.start(columns: columns, rows: rows, historyLineLimit: historyLineLimit) { result in continuation.resume(with: result) } } })
    }

    func updateViewport(_ size: CGSize) {
        viewport = size
        surfaces.values.forEach { $0.update(size: size) }
    }

    func surface(for paneID: TmuxPaneID) -> TmuxPaneSurface? { surfaces[paneID] }
    func selectWindow(_ id: TmuxWindowID) { controller.selectWindow(id) }
    func selectPane(_ id: TmuxPaneID) { controller.selectPane(id) }
    func mutateSharedWorkspace(_ mutation: TmuxClientCommandPolicy.SharedMutation) {
        controller.mutateSharedWorkspace(mutation)
    }

    /// DEBUG probe feeds output only after the surface registration fence.
    func feedDeterministicOutput(_ output: String) {
        controller.pump(Data(output.utf8))
        // The parser queue publishes output before it signals the renderer;
        // schedule after that serial feed has completed for the probe fixture.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.surfaces.values.forEach { $0.terminalChanged() }
        }
    }
    func sendInput(_ text: String, to pane: TmuxPaneID) { controller.sendInput(Data(text.utf8), to: pane, tracked: true) { _ in } }

    func stop() async {
        guard !stopped else { return }; gate.stop()
        controller.setOutboundSink(nil)
        await link.stop()
        while !creatingPaneIDs.isEmpty { await withCheckedContinuation { creationWaiters.append($0) } }
        let panes = Array(surfaces.values); surfaces.removeAll()
        for pane in panes { await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in pane.close { continuation.resume() } } }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in controller.shutdown { continuation.resume() } }
    }

    private func receive(_ state: TmuxSessionController.State, from id: UUID) { guard gate.accepts(id) else { return }; onState?(state) }
    private func receive(_ topology: TmuxSessionController.Topology, from id: UUID) { guard gate.accepts(id) else { return }; onTopology?(topology) }
    private func receiveInputFailure(_ message: String, from id: UUID) { guard gate.accepts(id) else { return }; onInputFailed?(message) }
    private func receive(_ terminal: TmuxSessionController.RetainedTerminal, from id: UUID) {
        guard gate.accepts(id), surfaces[terminal.paneID] == nil, creatingPaneIDs.insert(terminal.paneID).inserted else { return }
        TmuxPaneSurface.create(app: app, controller: controller, terminal: terminal, config: ghostty_terminal_surface_config_new(), size: viewport) { [weak self] pane in
            guard let self else { pane?.close(); return }
            self.creatingPaneIDs.remove(terminal.paneID)
            if self.creatingPaneIDs.isEmpty { let waiters = self.creationWaiters; self.creationWaiters.removeAll(); waiters.forEach { $0.resume() } }
            guard !self.stopped, id == self.instanceID else { pane?.close(); return }
            guard let pane else { return }
            self.surfaces[pane.paneID] = pane
            pane.terminalChanged()
            self.onSurface?(pane)
        }
    }
    private func remove(_ paneID: TmuxPaneID, from id: UUID) {
        guard gate.accepts(id), let pane = surfaces.removeValue(forKey: paneID) else { return }
        pane.close()
    }
    private final class Relay: @unchecked Sendable { weak var owner: GhosttyTmuxRuntime?; weak var controller: TmuxSessionController?; var id = UUID() }
}
