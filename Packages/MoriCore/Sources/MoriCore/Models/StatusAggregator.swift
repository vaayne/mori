import Foundation

/// Pure-logic aggregation of window badges, worktree states, and project states.
/// Priority ordering: error > waiting > unread > dirty > normal (.none).
public enum StatusAggregator {

    /// Derive a worktree-level alert state from its window badges.
    /// Returns the highest-priority badge mapped to AlertState.
    public static func worktreeAlertState(windowBadges: [WindowBadge]) -> AlertState {
        var highest: AlertState = .none
        for badge in windowBadges {
            let mapped = alertState(from: badge)
            if mapped > highest {
                highest = mapped
            }
        }
        return highest
    }

    /// Aggregate worktree-level alert states into a project-level alert state.
    /// Returns the highest-priority state across all worktrees.
    public static func projectAlertState(worktreeStates: [AlertState]) -> AlertState {
        worktreeStates.max() ?? .none
    }

    /// Compute project aggregate unread count from worktree unread counts.
    public static func projectUnreadCount(worktreeUnreadCounts: [Int]) -> Int {
        worktreeUnreadCounts.reduce(0, +)
    }

    /// Combine window badge alert state with git status into a final worktree alert state.
    /// Git dirty status contributes `.dirty` which sits between `.info` and `.unread` in priority.
    public static func worktreeAlertState(
        windowBadges: [WindowBadge],
        hasUncommittedChanges: Bool
    ) -> AlertState {
        var highest = worktreeAlertState(windowBadges: windowBadges)
        if hasUncommittedChanges {
            let dirtyState: AlertState = .dirty
            if dirtyState > highest {
                highest = dirtyState
            }
        }
        return highest
    }

    /// Map a WindowBadge to an AlertState.
    public static func alertState(from badge: WindowBadge) -> AlertState {
        switch badge {
        case .idle:
            return .none
        case .unread:
            return .unread
        case .running:
            return .info
        case .longRunning:
            return .warning
        case .waiting:
            return .waiting
        case .error:
            return .error
        case .agentDone:
            return .info
        }
    }

    /// Derive a window badge from pane-level information.
    /// Simple derivation: if any pane has unread output, badge is `.unread`; otherwise `.idle`.
    public static func windowBadge(hasUnreadOutput: Bool) -> WindowBadge {
        hasUnreadOutput ? .unread : .idle
    }

    /// Derive a window badge from richer pane-level state.
    /// Priority: error > waiting > longRunning > running > unread > idle.
    public static func windowBadge(
        hasUnreadOutput: Bool,
        isRunning: Bool,
        isLongRunning: Bool,
        agentState: AgentState
    ) -> WindowBadge {
        // Agent state takes highest priority when it indicates attention needed
        switch agentState {
        case .error:
            return .error
        case .waitingForInput:
            return .waiting
        case .completed:
            return .agentDone
        default:
            break
        }
        if isLongRunning { return .longRunning }
        if isRunning { return .running }
        if hasUnreadOutput { return .unread }
        return .idle
    }
}
