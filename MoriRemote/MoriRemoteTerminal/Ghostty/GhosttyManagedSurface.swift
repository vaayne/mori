import Foundation
import GhosttyKit
import UIKit

enum GhosttyRuntimeSelectionDirection {
    case previous
    case next

    func advancedIndex(from index: Int, count: Int) -> Int {
        precondition(count > 0)
        return switch self {
        case .previous: (index - 1 + count) % count
        case .next: (index + 1) % count
        }
    }
}

func ghosttyDiagnosticShortID(_ id: UUID?) -> String {
    guard let id else { return "nil" }
    return String(id.uuidString.prefix(8))
}

func ghosttyDiagnosticPointer(_ pointer: UnsafeMutableRawPointer?) -> String {
    guard let pointer else { return "nil" }
    return String(format: "0x%llx", UInt64(UInt(bitPattern: pointer)))
}

func ghosttyDiagnosticRect(_ rect: CGRect) -> String {
    String(
        format: "%.1fx%.1f@%.1f,%.1f",
        rect.width,
        rect.height,
        rect.minX,
        rect.minY
    )
}

func ghosttyDiagnosticSurfaceSize(_ size: ghostty_surface_size_s) -> String {
    "\(size.columns)x\(size.rows) cells \(size.width_px)x\(size.height_px)px cell=\(size.cell_width_px)x\(size.cell_height_px)"
}

/// Stable screen-facing projection of one concrete tmux pane surface.
/// The pane surface owns native lifetime and display updates; this type contains
/// only UIKit presentation state and direct terminal interaction forwarding.
@MainActor
final class GhosttyManagedSurface {
    let id: UUID
    let view: GhosttyKitSurfaceView
    private(set) var controlSurface: GhosttyKitControlSurface

    private weak var paneOwner: TmuxPaneSurface?
    private(set) var isFocused = false
    private(set) var isVisible = false
    private(set) var scrollState: GhosttySurfaceScrollState
    private(set) var scrollRoute: GhosttySurfaceScrollRoute
    var onScrollStateChange: (() -> Void)?
    var onDisplayUpdate: ((GhosttyManagedSurface, CGSize, CGFloat) -> Void)?
    var onLocalSelectionGeometryChange: (() -> Void)?

    private var displayUpdateTracker = GhosttySurfaceDisplayUpdateTracker()

    init(
        id: UUID,
        view: GhosttyKitSurfaceView,
        controlSurface: GhosttyKitControlSurface,
        paneOwner: TmuxPaneSurface,
        interactionState: GhosttySurfaceInteractionState
    ) {
        self.id = id
        self.view = view
        self.controlSurface = controlSurface
        self.paneOwner = paneOwner
        scrollState = interactionState.scrollState
        scrollRoute = interactionState.scrollRoute
    }

    func applyTerminalTheme(_ theme: TerminalTheme) {
        view.applyTerminalTheme(theme)
    }

    @discardableResult
    func sendInput(_ text: String) -> FocusedTerminalInputSubmissionResult {
        guard !text.isEmpty else { return .empty }
        guard controlSurface.sendInput(text) else { return .surfaceRejected }
        onLocalSelectionGeometryChange?()
        return .accepted
    }

    @discardableResult
    func sendPaste(_ text: String) -> FocusedTerminalInputSubmissionResult {
        guard !text.isEmpty else { return .empty }
        return controlSurface.sendPaste(text) ? .accepted : .surfaceRejected
    }

    @discardableResult
    func sendKeyEvent(_ event: GhosttySurfaceKeyEvent) -> FocusedTerminalInputSubmissionResult {
        guard controlSurface.sendKeyEvent(event) else { return .surfaceRejected }
        onLocalSelectionGeometryChange?()
        return .accepted
    }

    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        _ = controlSurface.setVisible(visible)
    }

    func setFocused(_ focused: Bool) {
        guard focused != isFocused else { return }
        isFocused = focused
        _ = controlSurface.setFocused(focused)
    }

    func prepareForPermanentRemoval() {
        onDisplayUpdate = nil
        onScrollStateChange = nil
        setFocused(false)
        setVisible(false)
        view.isHidden = true
        view.removeFromSuperview()
        onLocalSelectionGeometryChange?()
        onLocalSelectionGeometryChange = nil
    }

    func replaceControlSurface(_ replacement: GhosttyKitControlSurface) {
        controlSurface = replacement
        displayUpdateTracker.reset()
        refreshInteractionState()
        isFocused = false
        isVisible = false
    }

    @discardableResult
    func updateDisplay(size: CGSize, scale: CGFloat) -> Bool {
        guard let metrics = displayUpdateTracker.nextMetrics(size: size, scale: scale) else {
            return false
        }
        guard paneOwner?.updateDisplay(metrics: metrics) == true else { return false }
        onDisplayUpdate?(self, size, scale)
        onLocalSelectionGeometryChange?()
        return true
    }

    func refreshInteractionState() {
        let state = controlSurface.interactionState()
        let changed = state.scrollState != scrollState || state.scrollRoute != scrollRoute
        scrollState = state.scrollState
        scrollRoute = state.scrollRoute
        if changed { onScrollStateChange?() }
        onLocalSelectionGeometryChange?()
    }

    @discardableResult
    func sendMouseButton(_ event: GhosttySurfaceMouseButtonEvent) -> Bool {
        controlSurface.sendMouseButton(event)
    }

    func sendMousePosition(
        _ position: CGPoint,
        mods: GhosttySurfaceKeyEvent.Mods = []
    ) {
        _ = controlSurface.sendMousePosition(position, mods: mods)
    }

    func sendMouseScroll(_ event: GhosttySurfaceMouseScrollEvent) {
        _ = controlSurface.sendMouseScroll(event)
        refreshInteractionState()
    }

    @discardableResult
    func scrollToPosition(row: UInt64, cellOffset: Double) -> GhosttySurfaceScrollState {
        let next = controlSurface.scrollToPosition(row: row, cellOffset: cellOffset)
        guard next != scrollState else { return scrollState }
        scrollState = next
        onScrollStateChange?()
        onLocalSelectionGeometryChange?()
        return scrollState
    }

    func notifyLocalSelectionGeometryChanged() {
        onLocalSelectionGeometryChange?()
    }

    func isMouseCaptured() -> Bool {
        controlSurface.isMouseCaptured()
    }

    func diagnosticSummary() -> String {
        "surface=\(ghosttyDiagnosticShortID(id)) handle=\(String(describing: controlSurface.handle)) visible=\(isVisible) focused=\(isFocused) view=\(ghosttyDiagnosticRect(view.frame)) bounds=\(ghosttyDiagnosticRect(view.bounds)) size=\(ghosttyDiagnosticSurfaceSize(controlSurface.currentSize())) scroll=total:\(scrollState.total) offset:\(scrollState.offset) len:\(scrollState.len) route:\(scrollRoute)"
    }
}
