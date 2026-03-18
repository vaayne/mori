import Foundation

/// Runtime model representing a parsed tmux session.
/// Kept separate from MoriCore models; mapping happens at a higher layer.
public struct TmuxSession: Identifiable, Equatable, Sendable {
    public var id: String { sessionId }
    public let sessionId: String
    public let name: String
    public let windowCount: Int
    public let isAttached: Bool
    public var windows: [TmuxWindow]

    public init(
        sessionId: String,
        name: String,
        windowCount: Int = 0,
        isAttached: Bool = false,
        windows: [TmuxWindow] = []
    ) {
        self.sessionId = sessionId
        self.name = name
        self.windowCount = windowCount
        self.isAttached = isAttached
        self.windows = windows
    }

    /// Whether this session follows the Mori naming convention `ws::<project>::<worktree>`.
    public var isMoriSession: Bool {
        name.hasPrefix("ws::")
    }

    /// Extract the project slug from a Mori session name.
    public var projectSlug: String? {
        guard isMoriSession else { return nil }
        let parts = name.split(separator: "::", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return nil }
        return String(parts[1])
    }

    /// Extract the worktree slug from a Mori session name.
    public var worktreeSlug: String? {
        guard isMoriSession else { return nil }
        let parts = name.split(separator: "::", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return nil }
        return String(parts[2])
    }
}
