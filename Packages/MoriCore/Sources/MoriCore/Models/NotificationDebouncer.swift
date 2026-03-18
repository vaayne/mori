import Foundation

/// Events that warrant a macOS notification.
public enum NotificationEvent: String, Codable, Sendable, Equatable {
    case agentWaiting
    case commandError
    case longRunningComplete
}

/// Pure-logic debouncer that tracks window badge transitions and decides
/// whether a notification should fire. Testable without UNUserNotificationCenter.
public struct NotificationDebouncer: Sendable {

    /// Debounce window in seconds — suppress re-fire for same window+event within this interval.
    public static let debounceInterval: TimeInterval = 30

    /// Last fire time per (windowId, event) pair.
    private var lastFired: [String: Date] = []

    public init() {}

    /// Determine whether a notification should fire for a badge transition.
    ///
    /// - Parameters:
    ///   - windowId: The tmux window identifier.
    ///   - oldBadge: The previous badge (nil if window is new).
    ///   - newBadge: The current badge after this poll cycle.
    ///   - now: Current timestamp (injectable for testing).
    /// - Returns: A `NotificationEvent` if a notification should fire, nil otherwise.
    public mutating func shouldNotify(
        windowId: String,
        oldBadge: WindowBadge?,
        newBadge: WindowBadge,
        now: Date = Date()
    ) -> NotificationEvent? {
        let event: NotificationEvent? = detectTransition(oldBadge: oldBadge, newBadge: newBadge)

        guard let event else { return nil }

        // Check debounce
        let key = "\(windowId)::\(event.rawValue)"
        if let last = lastFired[key], now.timeIntervalSince(last) < Self.debounceInterval {
            return nil
        }

        lastFired[key] = now
        return event
    }

    /// Detect a notification-worthy transition between badge states.
    private func detectTransition(oldBadge: WindowBadge?, newBadge: WindowBadge) -> NotificationEvent? {
        let old = oldBadge ?? .idle

        // No transition — same badge
        if old == newBadge { return nil }

        switch newBadge {
        case .waiting:
            // Transitioned to waiting (agent needs input)
            return .agentWaiting
        case .error:
            // Transitioned to error
            return .commandError
        case .idle:
            // Was running/longRunning and now idle — long-running complete
            if old == .longRunning || old == .running {
                return .longRunningComplete
            }
            return nil
        default:
            return nil
        }
    }
}
