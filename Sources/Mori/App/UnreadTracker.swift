import Foundation
import MoriCore
import MoriTmux

/// Tracks unread output across tmux windows by comparing pane_activity timestamps
/// against last-seen values. In-memory only — on restart all windows are treated as "seen".
@MainActor
final class UnreadTracker {

    /// In-memory map: "worktreeId:windowId" -> last seen pane_activity timestamp.
    private var lastSeen: [String: TimeInterval] = [:]

    /// Process tmux sessions and detect windows with new activity.
    /// Returns composite keys (`worktreeId:windowId`) that have new unread output.
    ///
    /// For each Mori session matched to a worktree:
    /// - For each window, compute the max pane_activity across panes
    /// - Compare against lastSeen[key]
    /// - If newer, add windowId to result set and update lastSeen
    /// - If first time seeing this window, just record the timestamp (no unread)
    func processActivity(
        sessions: [TmuxSession],
        worktrees: [Worktree],
        selectedWindowId: String?
    ) -> Set<String> {
        var unreadWindowKeys: Set<String> = []

        for session in sessions where session.isMoriSession {
            // Match session to worktree
            guard let worktree = worktrees.first(where: {
                $0.tmuxSessionName == session.name
            }) else { continue }

            for tmuxWindow in session.windows {
                let key = "\(worktree.id):\(tmuxWindow.windowId)"

                // Compute max pane_activity for this window
                let maxActivity = tmuxWindow.panes
                    .compactMap { $0.lastActivity }
                    .max() ?? 0

                guard maxActivity > 0 else { continue }

                if let previousActivity = lastSeen[key] {
                    // We've seen this window before — check for new activity
                    if maxActivity > previousActivity {
                        // Skip the currently selected window (user is looking at it)
                        if tmuxWindow.windowId != selectedWindowId {
                            unreadWindowKeys.insert(key)
                        }
                        lastSeen[key] = maxActivity
                    }
                } else {
                    // First time seeing this window — record timestamp, no unread
                    lastSeen[key] = maxActivity
                }
            }
        }

        return unreadWindowKeys
    }

    /// Mark a window as "seen" (user selected it).
    /// Updates the last-seen timestamp so future polls won't flag it as unread.
    func markSeen(worktreeId: UUID, windowId: String, activity: TimeInterval) {
        let key = "\(worktreeId):\(windowId)"
        lastSeen[key] = activity
    }

    /// Get the current max pane activity for a window from session data.
    /// Useful when clearing unread on selection.
    func currentActivity(
        sessionName: String,
        windowId: String,
        in sessions: [TmuxSession]
    ) -> TimeInterval? {
        for session in sessions where session.name == sessionName {
            for window in session.windows where window.windowId == windowId {
                return window.panes
                    .compactMap { $0.lastActivity }
                    .max()
            }
        }
        return nil
    }

    // MARK: - Testing Support

    /// The number of tracked windows (for testing).
    var trackedCount: Int { lastSeen.count }

    /// Get the last-seen timestamp for a key (for testing).
    func lastSeenTimestamp(worktreeId: UUID, windowId: String) -> TimeInterval? {
        lastSeen["\(worktreeId):\(windowId)"]
    }
}
