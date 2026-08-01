import CoreGraphics
import Foundation
import QuartzCore

/// Maps radial travel from a fixed long-press origin to one cardinal direction
/// and three repeat-rate tiers. Each committed tier has a stable plateau before
/// travel begins arming the next tier.
struct GhosttyKeyboardCursorTrackpad {
    struct Configuration {
        var neutralRadius: CGFloat
        var armingDistance: CGFloat
        var tierPlateauDistance: CGFloat
        var oneXRepeatInterval: TimeInterval
        var twoXRepeatInterval: TimeInterval
        var threeXRepeatInterval: TimeInterval
        var directionSwitchRatio: CGFloat
        var tierReleaseHysteresis: CGFloat

        static let `default` = Configuration(
            neutralRadius: 8,
            armingDistance: 28,
            tierPlateauDistance: 14,
            oneXRepeatInterval: 0.45,
            twoXRepeatInterval: 0.225,
            threeXRepeatInterval: 0.12,
            directionSwitchRatio: 1.25,
            tierReleaseHysteresis: 4
        )
    }

    enum Direction: Equatable {
        case left
        case right
        case up
        case down

        var isHorizontal: Bool {
            self == .left || self == .right
        }
    }

    enum SpeedTier: Int, Equatable {
        case neutral = 0
        case one = 1
        case two = 2
        case three = 3
    }

    struct FeedbackState: Equatable {
        var isVisible: Bool
        var direction: Direction?
        var committedTier: SpeedTier
        var armingTier: SpeedTier?
        var armingProgress: CGFloat

        static let hidden = FeedbackState(
            isVisible: false,
            direction: nil,
            committedTier: .neutral,
            armingTier: nil,
            armingProgress: 0
        )

        static let active = FeedbackState(
            isVisible: true,
            direction: nil,
            committedTier: .neutral,
            armingTier: nil,
            armingProgress: 0
        )
    }

    let configuration: Configuration

    private var origin: CGPoint?
    private var direction: Direction?
    private var committedTier: SpeedTier = .neutral

    init(configuration: Configuration = .default) {
        precondition(configuration.neutralRadius >= 0, "neutralRadius must be non-negative")
        precondition(configuration.armingDistance > 0, "armingDistance must be positive")
        precondition(configuration.tierPlateauDistance >= 0, "tierPlateauDistance must be non-negative")
        precondition(configuration.oneXRepeatInterval > 0, "oneXRepeatInterval must be positive")
        precondition(configuration.twoXRepeatInterval > 0, "twoXRepeatInterval must be positive")
        precondition(configuration.threeXRepeatInterval > 0, "threeXRepeatInterval must be positive")
        precondition(configuration.directionSwitchRatio >= 1, "directionSwitchRatio must be at least 1")
        precondition(configuration.tierReleaseHysteresis >= 0, "tierReleaseHysteresis must be non-negative")
        precondition(
            configuration.tierReleaseHysteresis < configuration.armingDistance,
            "tierReleaseHysteresis must be shorter than armingDistance"
        )
        self.configuration = configuration
    }

    mutating func begin(at point: CGPoint) -> FeedbackState {
        origin = point
        direction = nil
        committedTier = .neutral
        return .active
    }

    mutating func update(at point: CGPoint) -> FeedbackState {
        guard let origin else {
            return begin(at: point)
        }

        let displacement = CGPoint(
            x: point.x - origin.x,
            y: point.y - origin.y
        )
        let radius = sqrt(
            displacement.x * displacement.x
                + displacement.y * displacement.y
        )
        guard radius > 0, radius >= configuration.neutralRadius else {
            direction = nil
            committedTier = .neutral
            return .active
        }

        direction = resolveDirection(for: displacement)
        guard let direction else { return .active }

        let speed = speedState(at: radius)

        return FeedbackState(
            isVisible: true,
            direction: direction,
            committedTier: speed.committedTier,
            armingTier: speed.armingTier,
            armingProgress: speed.armingProgress
        )
    }

    func repeatInterval(for tier: SpeedTier) -> TimeInterval? {
        switch tier {
        case .neutral: nil
        case .one: configuration.oneXRepeatInterval
        case .two: configuration.twoXRepeatInterval
        case .three: configuration.threeXRepeatInterval
        }
    }

    private mutating func speedState(
        at radius: CGFloat
    ) -> (committedTier: SpeedTier, armingTier: SpeedTier?, armingProgress: CGFloat) {
        let rawState = rawSpeedState(at: radius)

        if rawState.committedTier.rawValue > committedTier.rawValue {
            committedTier = rawState.committedTier
            return rawState
        }

        if rawState.committedTier.rawValue < committedTier.rawValue {
            let releaseRadius = activationRadius(for: committedTier)
                - configuration.tierReleaseHysteresis
            guard radius < releaseRadius else {
                return (committedTier, nil, 0)
            }
            committedTier = rawState.committedTier
        }

        return rawState
    }

    private func rawSpeedState(
        at radius: CGFloat
    ) -> (committedTier: SpeedTier, armingTier: SpeedTier?, armingProgress: CGFloat) {
        var remaining = radius - configuration.neutralRadius
        guard remaining >= 0 else { return (.neutral, nil, 0) }

        if remaining < configuration.armingDistance {
            return (.neutral, .one, remaining / configuration.armingDistance)
        }
        remaining -= configuration.armingDistance

        if remaining < configuration.tierPlateauDistance {
            return (.one, nil, 0)
        }
        remaining -= configuration.tierPlateauDistance

        if remaining < configuration.armingDistance {
            return (.one, .two, remaining / configuration.armingDistance)
        }
        remaining -= configuration.armingDistance

        if remaining < configuration.tierPlateauDistance {
            return (.two, nil, 0)
        }
        remaining -= configuration.tierPlateauDistance

        if remaining < configuration.armingDistance {
            return (.two, .three, remaining / configuration.armingDistance)
        }
        return (.three, nil, 0)
    }

    private func activationRadius(for tier: SpeedTier) -> CGFloat {
        guard tier != .neutral else { return configuration.neutralRadius }
        return configuration.neutralRadius
            + CGFloat(tier.rawValue) * configuration.armingDistance
            + CGFloat(tier.rawValue - 1) * configuration.tierPlateauDistance
    }

    private mutating func resolveDirection(for displacement: CGPoint) -> Direction {
        let proposed: Direction
        if abs(displacement.x) >= abs(displacement.y) {
            proposed = displacement.x >= 0 ? .right : .left
        } else {
            proposed = displacement.y >= 0 ? .down : .up
        }

        guard let direction else { return proposed }
        guard direction.isHorizontal != proposed.isHorizontal else { return proposed }

        let currentAxisDistance = direction.isHorizontal
            ? abs(displacement.x)
            : abs(displacement.y)
        let proposedAxisDistance = proposed.isHorizontal
            ? abs(displacement.x)
            : abs(displacement.y)
        guard proposedAxisDistance >= currentAxisDistance * configuration.directionSwitchRatio else {
            if direction.isHorizontal {
                return displacement.x >= 0 ? .right : .left
            }
            return displacement.y >= 0 ? .down : .up
        }
        return proposed
    }
}

/// Owns one anchored cursor-steering gesture and its single repeat scheduler.
@MainActor
final class GhosttyKeyboardCursorTrackpadDriver {
    enum HapticCue: Equatable {
        case tierChanged
        case neutralEntered
    }

    private struct RepeatState {
        var direction: GhosttyKeyboardCursorTrackpad.Direction
        var tier: GhosttyKeyboardCursorTrackpad.SpeedTier
        var nextFireAt: TimeInterval
    }

    private let configuration: GhosttyKeyboardCursorTrackpad.Configuration
    private let playHaptic: (HapticCue) -> Void
    private weak var owner: AnyObject?
    private var trackpad: GhosttyKeyboardCursorTrackpad?
    private var sendKeyEvent: ((GhosttySurfaceKeyEvent) -> Bool)?
    private var publishFeedback: ((GhosttyKeyboardCursorTrackpad.FeedbackState) -> Void)?
    private var repeatState: RepeatState?
    private var repeatTimer: Timer?
    private var didSteer = false

    init(
        configuration: GhosttyKeyboardCursorTrackpad.Configuration = .default,
        playHaptic: @escaping (HapticCue) -> Void = { cue in
            switch cue {
            case .tierChanged:
                Haptic.selection()
            case .neutralEntered:
                Haptic.tap(.soft)
            }
        }
    ) {
        self.configuration = configuration
        self.playHaptic = playHaptic
    }

    func begin(
        owner: AnyObject,
        at point: CGPoint,
        sendKeyEvent: @escaping (GhosttySurfaceKeyEvent) -> Bool,
        onFeedbackChange: @escaping (GhosttyKeyboardCursorTrackpad.FeedbackState) -> Void
    ) {
        cancelCurrentGesture()

        var trackpad = GhosttyKeyboardCursorTrackpad(configuration: configuration)
        let feedback = trackpad.begin(at: point)
        self.owner = owner
        self.trackpad = trackpad
        self.sendKeyEvent = sendKeyEvent
        publishFeedback = onFeedbackChange
        didSteer = false
        onFeedbackChange(feedback)
        Haptic.tap(.soft)
    }

    @discardableResult
    func update(
        owner: AnyObject,
        at point: CGPoint,
        now: TimeInterval = CACurrentMediaTime()
    ) -> GhosttyKeyboardCursorTrackpad.FeedbackState? {
        guard self.owner === owner, var trackpad else { return nil }

        let feedback = trackpad.update(at: point)
        self.trackpad = trackpad
        guard apply(feedback: feedback, now: now) else { return feedback }
        publishFeedback?(feedback)
        return feedback
    }

    /// Deterministic time injection for repeat behavior tests. Delayed ticks
    /// emit at most one key and never catch up a backlog.
    func repeatTick(at now: TimeInterval) {
        guard let state = repeatState, now >= state.nextFireAt else { return }
        repeatTimer?.invalidate()
        repeatTimer = nil

        guard emit(direction: state.direction) else {
            cancelCurrentGesture()
            return
        }

        guard let interval = trackpad?.repeatInterval(for: state.tier) else {
            stopRepeating()
            return
        }
        repeatState?.nextFireAt = now + interval
        scheduleRepeat(after: interval)
    }

    /// Returns whether this gesture sent or attempted any steering key. A
    /// non-owner gets `nil`, allowing a stationary terminal long press to
    /// continue into text selection.
    @discardableResult
    func end(owner: AnyObject) -> Bool? {
        guard self.owner === owner else { return nil }
        let result = didSteer
        cancelCurrentGesture()
        return result
    }

    @discardableResult
    func cancel(owner: AnyObject) -> Bool {
        guard self.owner === owner else { return false }
        cancelCurrentGesture()
        return true
    }

    private func apply(
        feedback: GhosttyKeyboardCursorTrackpad.FeedbackState,
        now: TimeInterval
    ) -> Bool {
        guard let direction = feedback.direction,
              feedback.committedTier != .neutral,
              let interval = trackpad?.repeatInterval(for: feedback.committedTier)
        else {
            let enteredNeutral = repeatState != nil
            stopRepeating()
            if enteredNeutral {
                playHaptic(.neutralEntered)
            }
            return true
        }

        guard let current = repeatState else {
            guard emit(direction: direction) else {
                cancelCurrentGesture()
                return false
            }
            playHaptic(.tierChanged)
            repeatState = RepeatState(
                direction: direction,
                tier: feedback.committedTier,
                nextFireAt: now + interval
            )
            scheduleRepeat(after: interval)
            return true
        }

        guard current.direction == direction else {
            stopRepeating()
            guard emit(direction: direction) else {
                cancelCurrentGesture()
                return false
            }
            playHaptic(.tierChanged)
            repeatState = RepeatState(
                direction: direction,
                tier: feedback.committedTier,
                nextFireAt: now + interval
            )
            scheduleRepeat(after: interval)
            return true
        }

        guard current.tier != feedback.committedTier else { return true }
        if feedback.committedTier.rawValue > current.tier.rawValue {
            guard emit(direction: direction) else {
                cancelCurrentGesture()
                return false
            }
        }
        playHaptic(.tierChanged)
        repeatState = RepeatState(
            direction: direction,
            tier: feedback.committedTier,
            nextFireAt: now + interval
        )
        scheduleRepeat(after: interval)
        return true
    }

    private func emit(direction: GhosttyKeyboardCursorTrackpad.Direction) -> Bool {
        didSteer = true
        return sendKeyEvent?(GhosttySurfaceKeyEvent(keyCode: direction.keyCode)) == true
    }

    private func scheduleRepeat(after delay: TimeInterval) {
        repeatTimer?.invalidate()
        let timer = Timer(
            timeInterval: max(delay, 0.001),
            target: self,
            selector: #selector(repeatTimerFired),
            userInfo: nil,
            repeats: false
        )
        RunLoop.main.add(timer, forMode: .common)
        repeatTimer = timer
    }

    private func stopRepeating() {
        repeatState = nil
        repeatTimer?.invalidate()
        repeatTimer = nil
    }

    private func cancelCurrentGesture() {
        let hadOwner = owner != nil
        trackpad = nil
        stopRepeating()
        if hadOwner {
            publishFeedback?(.hidden)
        }
        owner = nil
        sendKeyEvent = nil
        publishFeedback = nil
        didSteer = false
    }

    @objc private func repeatTimerFired() {
        repeatTick(at: CACurrentMediaTime())
    }
}

private extension GhosttyKeyboardCursorTrackpad.Direction {
    var keyCode: GhosttySurfaceKeyEvent.KeyCode {
        switch self {
        case .up: .arrowUp
        case .down: .arrowDown
        case .left: .arrowLeft
        case .right: .arrowRight
        }
    }
}
