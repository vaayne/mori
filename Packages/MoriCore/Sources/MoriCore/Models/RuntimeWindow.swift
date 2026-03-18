import Foundation

public struct RuntimeWindow: Identifiable, Codable, Equatable, Sendable {
    public var id: String { tmuxWindowId }
    public let tmuxWindowId: String
    public let worktreeId: UUID
    public var tmuxWindowIndex: Int
    public var title: String
    public var activePaneId: String?
    public var paneCount: Int
    public var cwd: String?
    public var commandSummary: String?
    public var hasUnreadOutput: Bool
    public var lastOutputAt: Date?
    public var badge: WindowBadge?

    public init(
        tmuxWindowId: String,
        worktreeId: UUID,
        tmuxWindowIndex: Int = 0,
        title: String = "",
        activePaneId: String? = nil,
        paneCount: Int = 1,
        cwd: String? = nil,
        commandSummary: String? = nil,
        hasUnreadOutput: Bool = false,
        lastOutputAt: Date? = nil,
        badge: WindowBadge? = nil
    ) {
        self.tmuxWindowId = tmuxWindowId
        self.worktreeId = worktreeId
        self.tmuxWindowIndex = tmuxWindowIndex
        self.title = title
        self.activePaneId = activePaneId
        self.paneCount = paneCount
        self.cwd = cwd
        self.commandSummary = commandSummary
        self.hasUnreadOutput = hasUnreadOutput
        self.lastOutputAt = lastOutputAt
        self.badge = badge
    }
}
