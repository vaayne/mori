import GhosttyKit
import SwiftUI
import UIKit

/// Hosts the single terminal surface presented by MoriRemote. Pane/window
/// topology belongs to the app-owned Navigator, never viewport layout.
struct GhosttySingleViewportView: View {
    let surfaceLookup: GhosttyManagedSurfaceLookup
    let projection: GhosttyTerminalViewportPresentationProjection
    let terminalTheme: TerminalTheme
    let trackpadDriver: GhosttyKeyboardCursorTrackpadDriver
    let onSurfaceTap: ((UUID) -> Void)?
    let onWindowSwipe: ((GhosttyRuntimeSelectionDirection) -> Void)?
    let sendKeyEvent: (GhosttySurfaceKeyEvent) -> Bool
    let onTrackpadFeedbackChange: (GhosttyKeyboardCursorTrackpad.FeedbackState) -> Void
    let isMouseCaptured: (UUID) -> Bool
    let submitMouseButton: ((UUID, GhosttySurfaceMouseButtonEvent) -> GhosttyMouseInputSubmissionOutcome)?
    let submitMousePosition: ((UUID, CGPoint, GhosttySurfaceKeyEvent.Mods) -> GhosttyMouseInputSubmissionOutcome)?
    let submitMouseScroll: ((UUID, GhosttySurfaceMouseScrollEvent) -> GhosttyMouseInputSubmissionOutcome)?

    var body: some View {
        GhosttySingleViewportRepresentable(
            surfaceLookup: surfaceLookup,
            projection: projection,
            terminalTheme: terminalTheme,
            trackpadDriver: trackpadDriver,
            onSurfaceTap: onSurfaceTap,
            onWindowSwipe: onWindowSwipe,
            sendKeyEvent: sendKeyEvent,
            onTrackpadFeedbackChange: onTrackpadFeedbackChange,
            isMouseCaptured: isMouseCaptured,
            submitMouseButton: submitMouseButton,
            submitMousePosition: submitMousePosition,
            submitMouseScroll: submitMouseScroll
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct GhosttySingleViewportRepresentable: UIViewRepresentable {
    let surfaceLookup: GhosttyManagedSurfaceLookup
    let projection: GhosttyTerminalViewportPresentationProjection
    let terminalTheme: TerminalTheme
    let trackpadDriver: GhosttyKeyboardCursorTrackpadDriver
    let onSurfaceTap: ((UUID) -> Void)?
    let onWindowSwipe: ((GhosttyRuntimeSelectionDirection) -> Void)?
    let sendKeyEvent: (GhosttySurfaceKeyEvent) -> Bool
    let onTrackpadFeedbackChange: (GhosttyKeyboardCursorTrackpad.FeedbackState) -> Void
    let isMouseCaptured: (UUID) -> Bool
    let submitMouseButton: ((UUID, GhosttySurfaceMouseButtonEvent) -> GhosttyMouseInputSubmissionOutcome)?
    let submitMousePosition: ((UUID, CGPoint, GhosttySurfaceKeyEvent.Mods) -> GhosttyMouseInputSubmissionOutcome)?
    let submitMouseScroll: ((UUID, GhosttySurfaceMouseScrollEvent) -> GhosttyMouseInputSubmissionOutcome)?

    func makeUIView(context: Context) -> GhosttySingleViewportContainerView {
        let view = GhosttySingleViewportContainerView()
        view.backgroundColor = terminalTheme.terminalBackgroundUIColor
        view.updateSelectionHandleStyle(terminalTheme.terminalChromeStyle)
        return view
    }

    func updateUIView(_ view: GhosttySingleViewportContainerView, context: Context) {
        view.backgroundColor = terminalTheme.terminalBackgroundUIColor
        view.updateSelectionHandleStyle(terminalTheme.terminalChromeStyle)
        view.update(
            projection: projection,
            surfaceLookup: surfaceLookup,
            trackpadDriver: trackpadDriver,
            onSurfaceTap: onSurfaceTap,
            onWindowSwipe: onWindowSwipe,
            sendKeyEvent: sendKeyEvent,
            onTrackpadFeedbackChange: onTrackpadFeedbackChange,
            isMouseCaptured: isMouseCaptured,
            submitMouseButton: submitMouseButton,
            submitMousePosition: submitMousePosition,
            submitMouseScroll: submitMouseScroll
        )
    }

    static func dismantleUIView(
        _ view: GhosttySingleViewportContainerView,
        coordinator: ()
    ) {
        view.dismantle()
    }
}

private final class GhosttySingleViewportContainerView: UIView,
    UIGestureRecognizerDelegate,
    @preconcurrency UIEditMenuInteractionDelegate
{
    private var surfaceLookup = GhosttyManagedSurfaceLookup.empty
    private var projection = GhosttyTerminalViewportPresentationProjection.empty
    private var activeContainer: GhosttyPaneScrollContainerView?
    private var activeSurfaceID: UUID?
    private var trackpadDriver: GhosttyKeyboardCursorTrackpadDriver?

    private var onSurfaceTap: ((UUID) -> Void)?
    private var onWindowSwipe: ((GhosttyRuntimeSelectionDirection) -> Void)?
    private var sendKeyEvent: ((GhosttySurfaceKeyEvent) -> Bool)?
    private var onTrackpadFeedbackChange: ((GhosttyKeyboardCursorTrackpad.FeedbackState) -> Void)?
    private var isMouseCaptured: (UUID) -> Bool = { _ in false }
    private var submitMouseButton: ((UUID, GhosttySurfaceMouseButtonEvent) -> GhosttyMouseInputSubmissionOutcome)?
    private var submitMousePosition: ((UUID, CGPoint, GhosttySurfaceKeyEvent.Mods) -> GhosttyMouseInputSubmissionOutcome)?
    private var submitMouseScroll: ((UUID, GhosttySurfaceMouseScrollEvent) -> GhosttyMouseInputSubmissionOutcome)?

    private var activePanAxis: GhosttySurfacePanGesture.Axis?
    private var didNavigateForActivePan = false
    private weak var localSelectionSurface: GhosttyManagedSurface?
    private weak var localSelectionControlSurface: GhosttyKitControlSurface?
    private var longPressOriginalPoint: CGPoint?
    private var selectionSnapshot = GhosttyLocalSelectionSnapshot.inactive

    private lazy var startSelectionHandle = makeSelectionHandle(
        endpoint: GHOSTTY_TERMINAL_SURFACE_SELECTION_ENDPOINT_START
    )
    private lazy var endSelectionHandle = makeSelectionHandle(
        endpoint: GHOSTTY_TERMINAL_SURFACE_SELECTION_ENDPOINT_END
    )

    private lazy var panRecognizer: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(
            target: self,
            action: #selector(handleSurfacePan(_:))
        )
        recognizer.maximumNumberOfTouches = 1
        recognizer.cancelsTouchesInView = false
        return recognizer
    }()

    private lazy var surfaceTapRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(
            target: self,
            action: #selector(handleSurfaceTap(_:))
        )
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        return recognizer
    }()

    private lazy var selectionLongPressRecognizer: UILongPressGestureRecognizer = {
        let recognizer = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handleSelectionLongPress(_:))
        )
        recognizer.minimumPressDuration = 0.45
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        return recognizer
    }()

    private lazy var selectionEditMenuInteraction = UIEditMenuInteraction(delegate: self)

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        panRecognizer.delegate = self
        surfaceTapRecognizer.require(toFail: selectionLongPressRecognizer)
        addGestureRecognizer(panRecognizer)
        addGestureRecognizer(selectionLongPressRecognizer)
        addGestureRecognizer(surfaceTapRecognizer)
        addInteraction(selectionEditMenuInteraction)
        addSubview(startSelectionHandle)
        addSubview(endSelectionHandle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let inset = (GhosttySelectionHandleView.hitTargetSize - startSelectionHandle.bounds.width) / 2
        guard !startSelectionHandle.isHidden,
              !endSelectionHandle.isHidden,
              startSelectionHandle.frame.insetBy(dx: -inset, dy: -inset).contains(point),
              endSelectionHandle.frame.insetBy(dx: -inset, dy: -inset).contains(point)
        else { return super.hitTest(point, with: event) }

        let startDistance = point.squaredDistance(to: startSelectionHandle.center)
        let endDistance = point.squaredDistance(to: endSelectionHandle.center)
        let handle = startDistance <= endDistance
            ? startSelectionHandle
            : endSelectionHandle
        return handle.hitTest(convert(point, to: handle), with: event)
    }

    func updateSelectionHandleStyle(_ style: GhosttyTerminalChromeStyle) {
        let fillColor = UIColor(style.accent)
        let borderColor = UIColor(style.accentForeground).cgColor
        startSelectionHandle.backgroundColor = fillColor
        endSelectionHandle.backgroundColor = fillColor
        startSelectionHandle.layer.borderColor = borderColor
        endSelectionHandle.layer.borderColor = borderColor
    }

    func update(
        projection: GhosttyTerminalViewportPresentationProjection,
        surfaceLookup: GhosttyManagedSurfaceLookup,
        trackpadDriver: GhosttyKeyboardCursorTrackpadDriver,
        onSurfaceTap: ((UUID) -> Void)?,
        onWindowSwipe: ((GhosttyRuntimeSelectionDirection) -> Void)?,
        sendKeyEvent: @escaping (GhosttySurfaceKeyEvent) -> Bool,
        onTrackpadFeedbackChange: @escaping (GhosttyKeyboardCursorTrackpad.FeedbackState) -> Void,
        isMouseCaptured: @escaping (UUID) -> Bool,
        submitMouseButton: ((UUID, GhosttySurfaceMouseButtonEvent) -> GhosttyMouseInputSubmissionOutcome)?,
        submitMousePosition: ((UUID, CGPoint, GhosttySurfaceKeyEvent.Mods) -> GhosttyMouseInputSubmissionOutcome)?,
        submitMouseScroll: ((UUID, GhosttySurfaceMouseScrollEvent) -> GhosttyMouseInputSubmissionOutcome)?
    ) {
        self.projection = projection
        self.surfaceLookup = surfaceLookup
        self.trackpadDriver = trackpadDriver
        self.onSurfaceTap = onSurfaceTap
        self.onWindowSwipe = onWindowSwipe
        self.sendKeyEvent = sendKeyEvent
        self.onTrackpadFeedbackChange = onTrackpadFeedbackChange
        self.isMouseCaptured = isMouseCaptured
        self.submitMouseButton = submitMouseButton
        self.submitMousePosition = submitMousePosition
        self.submitMouseScroll = submitMouseScroll

        if activePanAxis == .horizontal, !projection.canNavigateWindows {
            resetActivePanState()
        }
        let previousSurfaceID = activeSurfaceID
        syncActiveSurface()
        var shouldRestoreSelection = previousSurfaceID != activeSurfaceID
        if localSelectionSurface != nil {
            if exactLocalSelectionSurface() == nil {
                cancelLocalSelectionInteraction()
                shouldRestoreSelection = true
            } else {
                layoutSelectionHandles()
            }
        }
        if shouldRestoreSelection {
            restoreLocalSelectionIfPresent()
        }
        flushLayoutIfPossible()
    }

    func dismantle() {
        disableInteractions()
        resetActivePanState()
        if let container = activeContainer {
            retire(container: container)
        }
        activeContainer = nil
        activeSurfaceID = nil
        surfaceLookup = .empty
        projection = .empty

    }

    private func disableInteractions() {
        cancelLocalSelectionInteraction()
        onSurfaceTap = nil
        onWindowSwipe = nil
        sendKeyEvent = nil
        onTrackpadFeedbackChange = nil
        isMouseCaptured = { _ in false }
        submitMouseButton = nil
        submitMousePosition = nil
        submitMouseScroll = nil
        trackpadDriver = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutActiveSurface()
        layoutSelectionHandles()
    }

    private func syncActiveSurface() {
        let startedAt = GhosttyRuntimeTrace.perfEnabled
            ? GhosttyRuntimeTrace.nowNanos()
            : nil
        defer {
            if let startedAt {
                GhosttyRuntimeTrace.perf(
                    "viewport.sync surface=\(ghosttyDiagnosticShortID(projection.surfaceID)) attached=\(activeContainer == nil ? 0 : 1) elapsed_ms=\(GhosttyRuntimeTrace.elapsedMilliseconds(from: startedAt))"
                )
            }
        }

        guard let desiredID = projection.surfaceID else {
            cancelLocalSelectionInteraction()
            retireActiveContainer()
            return
        }

        if activeSurfaceID != desiredID {
            cancelLocalSelectionInteraction()
            retireActiveContainer()
        }
        guard let surface = surfaceLookup.managedSurface(for: desiredID) else {
            retireActiveContainer()
            return
        }

        let container = activeContainer ?? GhosttyPaneScrollContainerView()
        activeContainer = container
        activeSurfaceID = desiredID
        container.backgroundColor = .clear
        let changed = container.update(
            surface: surface,
            displayScale: effectiveScale,
            submitRouteForwardedMouseScroll: submitMouseScroll,
            submitRouteForwardedMousePosition: submitMousePosition
        )
        if container.superview !== self {
            container.removeFromSuperview()
            addSubview(container)
            bringSubviewToFront(startSelectionHandle)
            bringSubviewToFront(endSelectionHandle)
        }
        if changed {
            container.layoutIfNeeded()
        }
    }

    private func retireActiveContainer() {
        guard let container = activeContainer else {
            activeContainer?.removeFromSuperview()
            activeContainer = nil
            activeSurfaceID = nil
            return
        }
        retire(container: container)
        activeContainer = nil
        activeSurfaceID = nil
    }

    private func retire(container: GhosttyPaneScrollContainerView) {
        container.detachCurrentSurfaceForRemoval()
        container.removeFromSuperview()
    }

    private func layoutActiveSurface() {
        guard let surfaceID = activeSurfaceID,
              let container = activeContainer,
              let surface = surfaceLookup.managedSurface(for: surfaceID)
        else { return }

        let startedAt = GhosttyRuntimeTrace.perfEnabled
            ? GhosttyRuntimeTrace.nowNanos()
            : nil
        let targetFrame = bounds.integral
        let changedFrame = container.frame != targetFrame
        if changedFrame {
            container.frame = targetFrame
        }
        let changedContainer = container.update(
            surface: surface,
            displayScale: effectiveScale,
            submitRouteForwardedMouseScroll: submitMouseScroll,
            submitRouteForwardedMousePosition: submitMousePosition
        )
        if changedFrame || changedContainer {
            container.layoutIfNeeded()
        }
        GhosttyRuntimeTrace.flowEndIfActive(
            GhosttyRuntimeTrace.paneSwitchFlow,
            event: "presentation.reveal.ready",
            fields: [
                "surface_uuid": surface.id.uuidString,
                "wall_ns": "\(GhosttyRuntimeTrace.wallNanos())",
            ]
        )
        if let startedAt {
            GhosttyRuntimeTrace.perf(
                "viewport.layout bounds=\(ghosttyDiagnosticRect(bounds)) changed=\(changedFrame || changedContainer) elapsed_ms=\(GhosttyRuntimeTrace.elapsedMilliseconds(from: startedAt))"
            )
        }
    }

    private func flushLayoutIfPossible() {
        guard bounds.width > 1, bounds.height > 1 else {
            setNeedsLayout()
            return
        }
        layoutActiveSurface()
    }

    @objc
    private func handleSelectionLongPress(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            beginTerminalLongPress(recognizer)
        case .changed:
            updateTerminalLongPress(recognizer)
        case .ended:
            endTerminalLongPress()
        case .cancelled, .failed:
            reconcileLocalSelectionAfterLongPress()
        case .possible:
            break
        @unknown default:
            cancelLocalSelectionInteraction()
        }
    }

    private func beginTerminalLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard let driver = trackpadDriver,
              let surfaceID = projection.surfaceID,
              let surface = surfaceLookup.managedSurface(for: surfaceID),
              surface.view.isDescendant(of: self)
        else { return }

        cancelLocalSelectionInteraction()
        localSelectionSurface = surface
        localSelectionControlSurface = surface.controlSurface
        longPressOriginalPoint = recognizer.location(in: surface.view)
        surface.onLocalSelectionGeometryChange = { [weak self] in
            self?.refreshLocalSelectionGeometry()
        }
        driver.begin(
            owner: self,
            at: recognizer.location(in: surface.view),
            sendKeyEvent: { [weak self] event in
                guard self?.exactLocalSelectionSurface() != nil else { return false }
                return self?.sendKeyEvent?(event) == true
            },
            onFeedbackChange: { [weak self] state in
                self?.onTrackpadFeedbackChange?(state)
            }
        )
    }

    private func updateTerminalLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard let driver = trackpadDriver,
              let (surface, _) = exactLocalSelectionSurface()
        else {
            cancelLocalSelectionInteraction()
            return
        }
        _ = driver.update(owner: self, at: recognizer.location(in: surface.view))
    }

    private func endTerminalLongPress() {
        guard let driver = trackpadDriver else {
            cancelLocalSelectionInteraction()
            return
        }
        let didSteer = driver.end(owner: self)
        guard didSteer == false else {
            reconcileLocalSelectionAfterLongPress()
            return
        }

        guard let point = longPressOriginalPoint,
              let (_, control) = exactLocalSelectionSurface()
        else {
            cancelLocalSelectionInteraction()
            return
        }

        switch control.selectLink(at: point) {
        case .match(let snapshot, _):
            longPressOriginalPoint = nil
            applySelectionOutcome(.snapshot(snapshot), presentMenu: true)
        case .noMatch:
            longPressOriginalPoint = nil
            applySelectionOutcome(control.selectWord(at: point), presentMenu: true)
        case .unavailable:
            reconcileLocalSelectionAfterLongPress()
        }
    }

    private func presentSelectionCopyMenu() {
        guard selectionSnapshot.isActive,
              exactLocalSelectionSurface() != nil,
              let anchor = selectionMenuAnchorHandle
        else { return }
        selectionEditMenuInteraction.presentEditMenu(
            with: UIEditMenuConfiguration(
                identifier: nil,
                sourcePoint: anchor.center
            )
        )
    }

    private var selectionMenuAnchorHandle: GhosttySelectionHandleView? {
        if !endSelectionHandle.isHidden { return endSelectionHandle }
        if !startSelectionHandle.isHidden { return startSelectionHandle }
        return nil
    }

    @objc
    private func handleSurfaceTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              let surfaceID = projection.surfaceID,
              let surface = surfaceLookup.managedSurface(for: surfaceID)
        else { return }

        if selectionSnapshot.isActive,
           let (_, control) = exactLocalSelectionSurface() {
            _ = control.clearSelection()
            cancelLocalSelectionInteraction()
            return
        }

        let mouseCaptured = isMouseCaptured(surfaceID)
        if activeContainer?.consumeMomentumCatchTap() == true {
            return
        }
        for action in GhosttySurfaceTapGesture.actions(
            forLocalPoint: recognizer.location(in: surface.view),
            mouseCaptured: mouseCaptured
        ) {
            switch action {
            case .activateInput:
                onSurfaceTap?(surfaceID)
            case .mousePosition(let position):
                _ = submitMousePosition?(surfaceID, position, [])
            case .mouseButton(let event):
                _ = submitMouseButton?(surfaceID, event)
            }
        }
    }

    @objc
    private func handleSurfacePan(_ recognizer: UIPanGestureRecognizer) {
        guard let phase = GhosttySurfacePanGesture.Phase(recognizer.state) else { return }

        if phase == .began {
            resetActivePanState()
        }
        defer { resetActivePanStateIfEnded(phase) }

        guard let surfaceID = projection.surfaceID,
              surfaceLookup.managedSurface(for: surfaceID) != nil
        else { return }

        if longPressOriginalPoint != nil {
            return
        }

        let translation = recognizer.translation(in: self)
        activePanAxis = GhosttySurfacePanGesture.axis(
            forTranslation: translation,
            currentAxis: activePanAxis
        )
        if activePanAxis == .horizontal {
            routeHorizontalNavigation(
                translation: translation,
                velocity: recognizer.velocity(in: self)
            )
        }
    }

    private func routeHorizontalNavigation(translation: CGPoint, velocity: CGPoint) {
        guard projection.canNavigateWindows,
              let direction = GhosttySurfacePanGesture.windowNavigationDirection(
                forTranslation: translation,
                velocity: velocity,
                axis: .horizontal,
                didNavigate: didNavigateForActivePan
              )
        else { return }

        didNavigateForActivePan = true
        onWindowSwipe?(direction.runtimeSelectionDirection)
    }

    private func resetActivePanStateIfEnded(_ phase: GhosttySurfacePanGesture.Phase) {
        if phase == .ended || phase == .cancelled {
            resetActivePanState()
        }
    }

    private func resetActivePanState() {
        activePanAxis = nil
        didNavigateForActivePan = false
    }

    private func exactLocalSelectionSurface()
        -> (GhosttyManagedSurface, GhosttyKitControlSurface)? {
        guard let recordedSurface = projectedLocalSelectionSurface(),
              let recordedControl = localSelectionControlSurface,
              recordedSurface.controlSurface === recordedControl
        else { return nil }
        return (recordedSurface, recordedControl)
    }

    private func projectedLocalSelectionSurface() -> GhosttyManagedSurface? {
        guard let recordedSurface = localSelectionSurface,
              projection.surfaceID == recordedSurface.id,
              activeSurfaceID == recordedSurface.id,
              surfaceLookup.managedSurface(for: recordedSurface.id) === recordedSurface,
              recordedSurface.view.isDescendant(of: self)
        else { return nil }
        return recordedSurface
    }

    private func refreshLocalSelectionGeometry() {
        guard let surface = projectedLocalSelectionSurface() else {
            cancelLocalSelectionInteraction()
            return
        }
        let control = surface.controlSurface
        localSelectionControlSurface = control
        // Output during neutral/steering must not resurrect an older selection.
        guard longPressOriginalPoint == nil, selectionSnapshot.isActive else { return }
        applySelectionOutcome(control.selectionSnapshot(), presentMenu: false)
    }

    private func reconcileLocalSelectionAfterLongPress() {
        _ = trackpadDriver?.cancel(owner: self)
        longPressOriginalPoint = nil
        guard let surface = projectedLocalSelectionSurface() else {
            cancelLocalSelectionInteraction()
            return
        }
        localSelectionControlSurface = surface.controlSurface
        applySelectionOutcome(
            surface.controlSurface.selectionSnapshot(),
            presentMenu: false
        )
    }

    private func restoreLocalSelectionIfPresent() {
        guard localSelectionSurface == nil,
              let surfaceID = activeSurfaceID,
              let surface = surfaceLookup.managedSurface(for: surfaceID),
              surface.view.isDescendant(of: self),
              case .snapshot(let snapshot) = surface.controlSurface.selectionSnapshot(),
              snapshot.isActive
        else { return }

        localSelectionSurface = surface
        localSelectionControlSurface = surface.controlSurface
        surface.onLocalSelectionGeometryChange = { [weak self] in
            self?.refreshLocalSelectionGeometry()
        }
        selectionSnapshot = snapshot
        layoutSelectionHandles()
    }

    private func applySelectionOutcome(
        _ outcome: GhosttyLocalSelectionOutcome,
        presentMenu: Bool
    ) {
        guard case .snapshot(let snapshot) = outcome else {
            cancelLocalSelectionInteraction()
            return
        }
        selectionSnapshot = snapshot
        guard selectionSnapshot.isActive else {
            cancelLocalSelectionInteraction()
            return
        }
        layoutSelectionHandles()
        if presentMenu { presentSelectionCopyMenu() }
    }

    private func cancelLocalSelectionInteraction() {
        _ = trackpadDriver?.cancel(owner: self)
        localSelectionSurface?.onLocalSelectionGeometryChange = nil
        selectionEditMenuInteraction.dismissMenu()
        localSelectionSurface = nil
        localSelectionControlSurface = nil
        longPressOriginalPoint = nil
        selectionSnapshot = .inactive
        startSelectionHandle.isHidden = true
        endSelectionHandle.isHidden = true
    }

    private func makeSelectionHandle(
        endpoint: ghostty_terminal_surface_selection_endpoint_e
    ) -> GhosttySelectionHandleView {
        let handle = GhosttySelectionHandleView(endpoint: endpoint)
        handle.isHidden = true
        handle.addGestureRecognizer(UIPanGestureRecognizer(
            target: self,
            action: #selector(handleSelectionEndpointPan(_:))
        ))
        return handle
    }

    @objc
    private func handleSelectionEndpointPan(_ recognizer: UIPanGestureRecognizer) {
        guard let handle = recognizer.view as? GhosttySelectionHandleView,
              let (surface, control) = exactLocalSelectionSurface()
        else {
            cancelLocalSelectionInteraction()
            return
        }
        if recognizer.state == .began {
            selectionEditMenuInteraction.dismissMenu()
        }
        if recognizer.state == .changed {
            applySelectionOutcome(
                control.setSelectionEndpoint(
                    handle.endpoint,
                    at: recognizer.location(in: surface.view)
                ),
                presentMenu: false
            )
        } else if recognizer.state == .ended || recognizer.state == .cancelled {
            presentSelectionCopyMenu()
        }
    }

    private func layoutSelectionHandles() {
        guard selectionSnapshot.isActive,
              let (surface, _) = exactLocalSelectionSurface()
        else {
            startSelectionHandle.isHidden = true
            endSelectionHandle.isHidden = true
            return
        }
        position(startSelectionHandle, surface: surface)
        position(endSelectionHandle, surface: surface)
    }

    private func position(
        _ handle: GhosttySelectionHandleView,
        surface: GhosttyManagedSurface
    ) {
        let isStart = handle.endpoint == GHOSTTY_TERMINAL_SURFACE_SELECTION_ENDPOINT_START
        let rect = isStart ? selectionSnapshot.start : selectionSnapshot.end
        guard let rect else {
            handle.isHidden = true
            return
        }
        let anchor = isStart
            ? CGPoint(x: rect.minX, y: rect.minY)
            : CGPoint(x: rect.maxX, y: rect.maxY)
        let rawCenter = surface.view.convert(anchor, to: self)
        let inset = handle.bounds.width / 2
        handle.center = CGPoint(
            x: min(max(rawCenter.x, bounds.minX + inset), bounds.maxX - inset),
            y: min(max(rawCenter.y, bounds.minY + inset), bounds.maxY - inset)
        )
        handle.isHidden = false
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard gestureRecognizer === panRecognizer || otherGestureRecognizer === panRecognizer else {
            return false
        }
        return gestureRecognizer is UIPanGestureRecognizer &&
            otherGestureRecognizer is UIPanGestureRecognizer
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        _ = gestureRecognizer
        guard let touchedView = touch.view else { return true }
        return !touchedView.isDescendant(of: startSelectionHandle)
            && !touchedView.isDescendant(of: endSelectionHandle)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panRecognizer else { return true }
        return GhosttySurfacePanGesture.surfaceContainerPanShouldBegin(
            topLevelCount: projection.windowCount,
            velocity: panRecognizer.velocity(in: self)
        )
    }

    private var effectiveScale: CGFloat {
        max(window?.screen.scale ?? UIScreen.main.scale, 1)
    }

    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        menuFor configuration: UIEditMenuConfiguration,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        _ = interaction
        _ = configuration
        _ = suggestedActions
        guard selectionSnapshot.isActive,
              exactLocalSelectionSurface() != nil,
              selectionMenuAnchorHandle != nil
        else { return nil }

        guard let (_, control) = exactLocalSelectionSurface(),
              let selectedText = control.readSelection(),
              !selectedText.isEmpty
        else { return nil }

        var actions: [UIMenuElement] = []
        actions.append(
            UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                guard let (_, control) = self?.exactLocalSelectionSurface(),
                      let text = control.readSelection(),
                      !text.isEmpty
                else { return }
                UIPasteboard.general.string = text
            }
        )
        return UIMenu(children: actions)
    }

    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        targetRectFor configuration: UIEditMenuConfiguration
    ) -> CGRect {
        _ = interaction
        _ = configuration
        return selectionMenuAnchorHandle?.frame ?? .zero
    }
}

private final class GhosttySelectionHandleView: UIView {
    static let hitTargetSize: CGFloat = 44
    let endpoint: ghostty_terminal_surface_selection_endpoint_e

    init(endpoint: ghostty_terminal_surface_selection_endpoint_e) {
        self.endpoint = endpoint
        super.init(frame: CGRect(x: 0, y: 0, width: 18, height: 18))
        layer.borderWidth = 1
        layer.cornerRadius = 9
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        _ = event
        let inset = (Self.hitTargetSize - bounds.width) / 2
        return bounds.insetBy(dx: -inset, dy: -inset).contains(point)
    }
}

private extension CGPoint {
    func squaredDistance(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return dx * dx + dy * dy
    }
}

private extension GhosttySurfacePanGesture.WindowNavigationDirection {
    var runtimeSelectionDirection: GhosttyRuntimeSelectionDirection {
        switch self {
        case .previous: .previous
        case .next: .next
        }
    }
}
