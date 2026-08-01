import CoreGraphics
import Foundation

/// Stateful terminal-screen composition used by `GhosttyTerminalCoreView`.
/// It joins the upstream keyboard visibility projection to the viewport hold
/// coordinator; keeping the pair together prevents a keyboard notification
/// from changing chrome intent without preserving renderer geometry.
struct GhosttyTerminalCompositionState: Equatable {
    var inputCoordinator = GhosttyTerminalInputCoordinator()
    var viewportCoordinator = GhosttyTerminalViewportCoordinator()
    var keyboardTransitionCoordinator = GhosttyKeyboardViewportTransitionCoordinator()
    private(set) var keyboardOverlapHeight: CGFloat = 0

    mutating func reconcileViewport(_ size: CGSize) -> GhosttyTerminalViewportLiveSizeObservation {
        viewportCoordinator.reconcileLiveSize(size)
    }

    mutating func applyKeyboardVisibility(
        frameEnd: CGRect,
        screenBounds: CGRect,
        animationDuration: TimeInterval?
    ) -> GhosttyKeyboardViewportTransitionRequest? {
        let projection = GhosttyKeyboardVisibilityProjection(
            frameEnd: frameEnd,
            screenBounds: screenBounds,
            animationDuration: animationDuration,
            keyboardMode: inputCoordinator.keyboardMode,
            isDismissSystemKeyboardRequested: inputCoordinator.isDismissSystemKeyboardRequested
        )
        keyboardOverlapHeight = projection.overlapHeight
        inputCoordinator.updateSoftwareKeyboardVisibility(projection.isVisible)
        keyboardTransitionCoordinator.observeKeyboardVisibility(isVisible: projection.isVisible)
        return projection.transitionRequest
    }

    mutating func beginKeyboardTransition(
        _ request: GhosttyKeyboardViewportTransitionRequest
    ) -> GhosttyKeyboardViewportTransitionBeginResult {
        keyboardTransitionCoordinator.beginTransition(
            request,
            viewportCoordinator: &viewportCoordinator,
            liveSize: viewportCoordinator.latestLiveSize
        )
    }

    mutating func completeKeyboardTransition(
        token: UInt64? = nil
    ) -> GhosttyKeyboardViewportTransitionCompletionResult? {
        if let token {
            return keyboardTransitionCoordinator.completeTransitionFromFallback(
                token: token,
                viewportCoordinator: &viewportCoordinator,
                liveSize: viewportCoordinator.latestLiveSize
            )
        }
        return keyboardTransitionCoordinator.completeTransition(
            viewportCoordinator: &viewportCoordinator,
            liveSize: viewportCoordinator.latestLiveSize
        )
    }
}
