import Combine
import CoreGraphics
import Foundation
import GhosttyKit


/// Projects one `TmuxTerminalSession` into the active MoriRemote viewport and
/// routes local input back to its retained pane surface.
///
/// Topology mapping: tmux window/pane IDs (UInt64) are mapped to stable UUIDs
/// for the screen's projections. The session may retain multiple real pane
/// surfaces, while this adapter publishes only the active pane's stable
/// `GhosttyManagedSurface` to the phone viewport.
@MainActor
final class TmuxTerminalScreenAdapter: ObservableObject {
    private weak var session: TmuxTerminalSession?
    private var controller: TmuxSessionController?

    /// The last topology emitted by `session.$topology`. All adapter reads go
    /// through this value, never `session.topology`: `@Published` emits from
    /// `willSet`, so reading the property inside a sink returns the previous
    /// snapshot and the projection lags one topology update behind.
    private var latestTopology: TmuxSessionController.TopologySnapshot?

    private var activeManagedSurface: GhosttyManagedSurface?
    private var initialViewportHandler: ((CGSize, CGFloat) -> Void)?
    private var clientSizeHandler: ((TmuxSessionController.ClientSize) -> Void)?
    private var viewportStabilityHandler: ((Bool) -> Void)?

    private var subscriptions: [AnyCancellable] = []

    /// Connects the adapter to a live session. Called once, right after the
    /// session is created.
    func activate(
        session: TmuxTerminalSession,
        initialViewportHandler: @escaping (CGSize, CGFloat) -> Void,
        clientSizeHandler: @escaping (TmuxSessionController.ClientSize) -> Void = { _ in },
        viewportStabilityHandler: @escaping (Bool) -> Void = { _ in }
    ) {
        self.session = session
        self.controller = session.controller
        self.initialViewportHandler = initialViewportHandler
        self.clientSizeHandler = clientSizeHandler
        self.viewportStabilityHandler = viewportStabilityHandler

        session.$state
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &subscriptions)
        // Subscribed before $paneSurface so the replayed initial value seeds
        // latestTopology ahead of the surface rebuild below.
        session.$topology
            .sink { [weak self] topology in
                guard let self else { return }
                self.latestTopology = topology
                self.objectWillChange.send()
            }
            .store(in: &subscriptions)
        session.$paneSurface
            .sink { [weak self] paneSurface in
                self?.rebuildActiveManagedSurface(for: paneSurface)
                self?.objectWillChange.send()
            }
            .store(in: &subscriptions)
    }

    func invalidate() {
        subscriptions.removeAll()
        activeManagedSurface = nil
        session = nil
        controller = nil
        initialViewportHandler = nil
        clientSizeHandler = nil
        viewportStabilityHandler = nil
        latestTopology = nil
    }

    private var isTransportWritable: Bool {
        session?.state == .ready
    }

    // MARK: Managed surface lifecycle

    private func rebuildActiveManagedSurface(for paneSurface: TmuxPaneSurface?) {
        activeManagedSurface = paneSurface?.screenSurface { [weak self] managed, _, _ in
            self?.reportClientSizeIfActive(managed)
        }
    }

    private func managedSurface(for id: UUID) -> GhosttyManagedSurface? {
        if let active = activeManagedSurface, active.id == id {
            return active
        }
        return nil
    }

    private var focusedManagedSurface: GhosttyManagedSurface? {
        activeManagedSurface
    }

    private func reportClientSizeIfActive(_ managed: GhosttyManagedSurface) {
        guard activeManagedSurface === managed else { return }
        let size = managed.controlSurface.currentSize()
        guard size.columns >= 2, size.rows >= 2 else { return }
        clientSizeHandler?(.init(cols: UInt32(size.columns), rows: UInt32(size.rows)))
    }
}

extension TmuxTerminalScreenAdapter {
    func prepareInitialViewport(size: CGSize, scale: CGFloat) {
        initialViewportHandler?(size, scale)
    }

    func setViewportStabilityHint(stable: Bool) {
        viewportStabilityHandler?(stable)
    }

    var terminalViewportPresentationProjection: GhosttyTerminalViewportPresentationProjection {
        GhosttyTerminalViewportPresentationProjection(
            surfaceID: activeManagedSurface?.id,
            windowCount: latestTopology?.windows.count ?? 0
        )
    }

    /// A read-only summary for phone chrome. It reflects tmux topology only.
    var terminalChromeTopologyProjection: GhosttyTerminalChromeTopologyProjection {
        let windows = latestTopology?.windows ?? []
        let activeWindowID = latestTopology?.activeWindowID
        let selectedWindowIndex = activeWindowID.flatMap { id in
            windows.firstIndex(where: { $0.id == id })
        }
        let panes = activeWindowID.flatMap { activeID in
            latestTopology?.panes.filter { $0.windowID == activeID }
        } ?? []
        let activePaneID = windows.first(where: { $0.id == activeWindowID })?.activePaneID

        return GhosttyTerminalChromeTopologyProjection(
            selectedWindowIndex: selectedWindowIndex,
            windowCount: windows.count,
            selectedPaneIndex: activePaneID.flatMap { id in
                panes.firstIndex(where: { $0.id == id })
            },
            paneCount: panes.count
        )
    }

    var isInputAvailable: Bool {
        isTransportWritable && activeManagedSurface != nil
    }

    var terminalManagedSurfaceLookup: GhosttyManagedSurfaceLookup {
        GhosttyManagedSurfaceLookup { [weak self] id in
            self?.managedSurface(for: id)
        }
    }

    var stateTraceLabel: String {
        guard let session else { return "released" }
        return switch session.state {
        case .detached: "detached"
        case .attaching: "attaching"
        case .syncing: "syncing"
        case .ready: "ready"
        case .closed: "closed"
        }
    }

    // MARK: Input routing

    private func preflightFocusedInput() -> FocusedTerminalInputSubmissionResult? {
        guard isTransportWritable else { return .transportUnavailable }
        guard focusedManagedSurface != nil else { return .noFocusedSurface }
        return nil
    }

    func sendInputToFocusedSurface(_ text: String) -> FocusedTerminalInputSubmissionResult {
        if let preflight = preflightFocusedInput() { return preflight }
        return focusedManagedSurface?.sendInput(text) ?? .noFocusedSurface
    }

    func sendPasteToFocusedSurface(_ text: String) -> FocusedTerminalInputSubmissionResult {
        if let preflight = preflightFocusedInput() { return preflight }
        return focusedManagedSurface?.sendPaste(text) ?? .noFocusedSurface
    }

    func sendKeyEventToFocusedSurface(_ event: GhosttySurfaceKeyEvent) -> FocusedTerminalInputSubmissionResult {
        if let preflight = preflightFocusedInput() { return preflight }
        return focusedManagedSurface?.sendKeyEvent(event) ?? .noFocusedSurface
    }

    func isMouseCaptured(for surfaceID: UUID) -> Bool {
        managedSurface(for: surfaceID)?.controlSurface.isMouseCaptured() ?? false
    }

    func sendMouseButton(
        to surfaceID: UUID,
        _ event: GhosttySurfaceMouseButtonEvent
    ) -> GhosttyMouseInputSubmissionOutcome {
        guard let managed = managedSurface(for: surfaceID) else {
            return .missingTarget(surfaceID)
        }
        return managed.sendMouseButton(event) ? .sent : .surfaceRejected
    }

    func sendMousePosition(
        to surfaceID: UUID,
        _ position: CGPoint,
        mods: GhosttySurfaceKeyEvent.Mods
    ) -> GhosttyMouseInputSubmissionOutcome {
        guard let managed = managedSurface(for: surfaceID) else {
            return .missingTarget(surfaceID)
        }
        managed.sendMousePosition(position, mods: mods)
        return .sent
    }

    func sendMouseScroll(
        to surfaceID: UUID,
        _ event: GhosttySurfaceMouseScrollEvent
    ) -> GhosttyMouseInputSubmissionOutcome {
        guard let managed = managedSurface(for: surfaceID) else {
            return .missingTarget(surfaceID)
        }
        managed.sendMouseScroll(event)
        return .sent
    }

    // MARK: tmux topology actions

    func focusAdjacentTmuxTopLevel(
        _ direction: GhosttyRuntimeSelectionDirection
    ) {
        guard
            let controller,
            let topology = latestTopology,
            !topology.windows.isEmpty,
            let activeWindowID = topology.activeWindowID,
            let activeIndex = topology.windows.firstIndex(where: { $0.id == activeWindowID })
        else { return }

        let targetIndex = direction.advancedIndex(
            from: activeIndex,
            count: topology.windows.count
        )
        guard targetIndex != activeIndex else { return }
        let targetWindow = topology.windows[targetIndex]
        requestWindowSelection(targetWindow, in: topology, controller: controller)
    }

    private func requestWindowSelection(
        _ targetWindow: TmuxSessionController.WindowInfo,
        in topology: TmuxSessionController.TopologySnapshot,
        controller: TmuxSessionController
    ) {
        if topology.activeWindowID != targetWindow.id,
           let targetPaneID = targetWindow.activePaneID {
            session?.prepareForPaneSelection(paneID: targetPaneID)
        }

        controller.requestSelectWindow(
            windowID: targetWindow.id,
            preferredPaneID: targetWindow.activePaneID
        )
    }

}
