import CoreGraphics
import Foundation
import GhosttyKit

/// The model surface `GhosttyTerminalCoreView` renders against: projections
/// of terminal readiness/topology, focused-surface input routing, and tmux
/// topology actions.
///
/// The tmux session stack implements it (`TmuxTerminalScreenAdapter`). The
/// screen owns presentation behavior only; everything engine-specific flows
/// through this boundary.
enum GhosttyTmuxModelActionOutcome: Equatable, Sendable {
    case queued
    case missingTarget(GhosttyTmuxActionMissingTarget)

    var isHandled: Bool {
        switch self {
        case .queued:
            true
        case .missingTarget:
            false
        }
    }

    var isQueued: Bool {
        self == .queued
    }
}

struct GhosttyTmuxCommandFailureEvent: Equatable {
    let token: UInt64
    let message: String
}

/// App-level scene lifecycle phases forwarded into terminal screen models.
enum GhosttyAppLifecyclePhase: Equatable {
    case active
    case inactive
    case background
}

@MainActor
protocol GhosttyTerminalRenderingModeling: ObservableObject {
    var terminalScreenPresentationProjection: GhosttyTerminalScreenPresentationProjection { get }
    var terminalInteractionProjection: GhosttyTerminalInteractionProjection { get }
    var terminalManagedSurfaceLookup: GhosttyManagedSurfaceLookup { get }
    var commandFailureEvent: GhosttyTmuxCommandFailureEvent? { get }
    var stateTraceLabel: String { get }

    func prepareInitialViewport(size: CGSize, scale: CGFloat)

    /// Host hint that the terminal viewport is (not) in its settled
    /// shape — false while a transient overlay (software keyboard) is
    /// changing the layout. Engines use it to decide which reported
    /// viewport is safe to carry into a reconnect.
    func setViewportStabilityHint(stable: Bool)
}

@MainActor
protocol GhosttyTerminalInputModeling: ObservableObject {
    // MARK: Focused/targeted input routing

    @discardableResult
    func sendInputToFocusedSurface(_ text: String) -> FocusedTerminalInputSubmissionResult

    @discardableResult
    func sendPasteToFocusedSurface(_ text: String) -> FocusedTerminalInputSubmissionResult

    @discardableResult
    func sendPaste(_ text: String, to surfaceID: UUID) -> FocusedTerminalInputSubmissionResult

    func sendPasteAwaitingCommandCompletion(_ text: String, to surfaceID: UUID) async -> Bool

    @discardableResult
    func sendKeyEvent(
        _ event: GhosttySurfaceKeyEvent,
        to surfaceID: UUID
    ) -> FocusedTerminalInputSubmissionResult

    func sendKeyEventAwaitingCommandCompletion(
        _ event: GhosttySurfaceKeyEvent,
        to surfaceID: UUID
    ) async -> Bool

    @discardableResult
    func sendKeyEventToFocusedSurface(_ event: GhosttySurfaceKeyEvent) -> FocusedTerminalInputSubmissionResult

    func isMouseCaptured(for surfaceID: UUID) -> Bool

    @discardableResult
    func sendMouseButton(
        to surfaceID: UUID,
        _ event: GhosttySurfaceMouseButtonEvent
    ) -> GhosttyMouseInputSubmissionOutcome

    @discardableResult
    func sendMousePosition(
        to surfaceID: UUID,
        _ position: CGPoint,
        mods: GhosttySurfaceKeyEvent.Mods
    ) -> GhosttyMouseInputSubmissionOutcome

    @discardableResult
    func sendMouseScroll(
        to surfaceID: UUID,
        _ event: GhosttySurfaceMouseScrollEvent
    ) -> GhosttyMouseInputSubmissionOutcome

}

@MainActor
protocol GhosttyTmuxActionModeling: ObservableObject {
    // MARK: tmux topology actions

    @discardableResult
    func focusTmuxPane(_ id: UUID) -> GhosttyTmuxModelActionOutcome

    @discardableResult
    func focusTmuxTopLevel(_ id: UUID) -> GhosttyTmuxModelActionOutcome

    @discardableResult
    func focusAdjacentTmuxTopLevel(
        _ direction: GhosttyRuntimeSelectionDirection
    ) -> GhosttyTmuxModelActionOutcome
}

@MainActor
protocol GhosttyTerminalScreenModeling:
    GhosttyTerminalRenderingModeling,
    GhosttyTerminalInputModeling,
    GhosttyTmuxActionModeling
{}
