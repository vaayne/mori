import CoreGraphics
import UIKit

struct GhosttySurfacePanGesture {
    enum Axis: Equatable {
        case horizontal
        case vertical
    }

    enum WindowNavigationDirection: Equatable {
        case previous
        case next
    }

    enum Phase: Equatable {
        case began
        case changed
        case ended
        case cancelled

        var momentum: GhosttySurfaceMouseScrollMods.Momentum {
            switch self {
            case .began:
                .began
            case .changed:
                .changed
            case .ended:
                .ended
            case .cancelled:
                .cancelled
            }
        }
    }

    private static let dominantAxisTolerance: CGFloat = 1.5
    private static let activationThreshold: CGFloat = 6
    private static let windowNavigationTranslationThreshold: CGFloat = 56
    private static let windowNavigationVelocityThreshold: CGFloat = 480

    static func horizontalNavigationShouldBegin(forVelocity velocity: CGPoint) -> Bool {
        dominantAxis(forVelocity: velocity) == .horizontal
    }

    static func surfaceContainerPanShouldBegin(
        topLevelCount: Int,
        velocity: CGPoint
    ) -> Bool {
        guard topLevelCount > 1 else { return false }
        return dominantAxis(forVelocity: velocity) != .vertical
    }

    static func verticalScrollShouldBegin(forVelocity velocity: CGPoint) -> Bool {
        dominantAxis(forVelocity: velocity) == .vertical
    }

    static func routeForwardingScrollShouldBegin(
        forVelocity velocity: CGPoint,
        translation: CGPoint
    ) -> Bool {
        if let translationAxis = axis(forTranslation: translation) {
            return translationAxis == .vertical
        }

        return verticalScrollShouldBegin(forVelocity: velocity)
    }

    static func axis(
        forTranslation translation: CGPoint,
        currentAxis: Axis? = nil
    ) -> Axis? {
        if let currentAxis {
            return currentAxis
        }

        let absX = abs(translation.x)
        let absY = abs(translation.y)

        guard absX >= activationThreshold || absY >= activationThreshold else {
            return nil
        }

        if absY >= absX * dominantAxisTolerance {
            return .vertical
        }

        if absX >= absY * dominantAxisTolerance {
            return .horizontal
        }

        return nil
    }

    static func windowNavigationDirection(
        forTranslation translation: CGPoint,
        velocity: CGPoint,
        axis: Axis,
        didNavigate: Bool
    ) -> WindowNavigationDirection? {
        guard axis == .horizontal, !didNavigate else { return nil }

        let absX = abs(translation.x)
        let absY = abs(translation.y)
        let absVelocityX = abs(velocity.x)
        let absVelocityY = abs(velocity.y)
        let hasHorizontalTranslation =
            absX >= windowNavigationTranslationThreshold &&
            absX >= absY * dominantAxisTolerance
        let hasHorizontalVelocity =
            absVelocityX >= windowNavigationVelocityThreshold &&
            absVelocityX >= absVelocityY * dominantAxisTolerance

        guard hasHorizontalTranslation || hasHorizontalVelocity else {
            return nil
        }

        let directionValue = absX >= activationThreshold ? translation.x : velocity.x
        guard directionValue != 0 else { return nil }

        return directionValue < 0 ? .next : .previous
    }

    private static func dominantAxis(forVelocity velocity: CGPoint) -> Axis? {
        let absX = abs(velocity.x)
        let absY = abs(velocity.y)

        guard absX >= activationThreshold || absY >= activationThreshold else {
            return nil
        }

        if absY >= absX * dominantAxisTolerance {
            return .vertical
        }

        if absX >= absY * dominantAxisTolerance {
            return .horizontal
        }

        return nil
    }
}

struct GhosttyRouteForwardingScrollGesture {
    /// Default multiplier from gesture translation points to precise
    /// scroll units.
    static let defaultPreciseScale: CGFloat = 2
    private static let minimumPreciseDelta: Double = 1

    /// Multiplier from gesture translation points to precise scroll
    /// units. Fixed for the gesture's lifetime: a gain that varies
    /// mid-gesture would make the same drag distance scroll different
    /// amounts depending on speed history.
    let preciseScale: CGFloat

    private var pendingTranslation = CGPoint.zero
    private var hasBegun = false

    init(preciseScale: CGFloat = Self.defaultPreciseScale) {
        self.preciseScale = preciseScale
    }

    mutating func events(
        forTranslation translation: CGPoint,
        phase: GhosttySurfacePanGesture.Phase = .changed
    ) -> [GhosttySurfaceMouseScrollEvent] {
        pendingTranslation.x += translation.x
        pendingTranslation.y += translation.y

        let deltaY = Double(pendingTranslation.y * preciseScale)
        let isTerminalPhase = phase == .ended || phase == .cancelled
        let hasDispatchableDelta = abs(deltaY) >= Self.minimumPreciseDelta

        if !hasBegun {
            guard hasDispatchableDelta else {
                if isTerminalPhase {
                    reset()
                }
                return []
            }

            hasBegun = true
            pendingTranslation = .zero

            var events = [
                Self.event(deltaY: deltaY, phase: .began),
            ]
            if isTerminalPhase {
                events.append(Self.event(deltaY: 0, phase: phase))
                reset()
            }
            return events
        }

        if isTerminalPhase {
            let event = Self.event(deltaY: deltaY, phase: phase)
            reset()
            return [event]
        }

        guard hasDispatchableDelta else {
            return []
        }

        pendingTranslation = .zero
        return [Self.event(deltaY: deltaY, phase: .changed)]
    }

    mutating func reset() {
        pendingTranslation = .zero
        hasBegun = false
    }

    private static func event(
        deltaY: Double,
        phase: GhosttySurfacePanGesture.Phase
    ) -> GhosttySurfaceMouseScrollEvent {
        GhosttySurfaceMouseScrollEvent(
            deltaX: 0,
            deltaY: deltaY,
            mods: .init(precision: true, momentum: phase.momentum)
        )
    }
}

extension GhosttySurfacePanGesture.Phase {
    init?(_ state: UIGestureRecognizer.State) {
        switch state {
        case .began:
            self = .began
        case .changed:
            self = .changed
        case .ended:
            self = .ended
        case .cancelled, .failed:
            self = .cancelled
        case .possible:
            return nil
        @unknown default:
            return nil
        }
    }
}
