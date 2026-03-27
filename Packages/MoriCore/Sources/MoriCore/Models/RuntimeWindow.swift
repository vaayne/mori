import Foundation

public struct RuntimeWindow: Identifiable, Codable, Equatable, Sendable {
    public var id: String { tmuxWindowId }
    public let tmuxWindowId: String
    /// Raw tmux window ID returned by tmux (e.g. "@1"), without endpoint namespacing.
    public var tmuxWindowRawId: String?
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
    public var tag: WindowTag?
    public var lastExitCode: Int?
    public var isRunning: Bool
    public var isLongRunning: Bool
    public var agentState: AgentState
    /// Process name of a detected coding agent (e.g. "claude", "codex"), nil if none.
    public var detectedAgent: String?

    public init(
        tmuxWindowId: String,
        tmuxWindowRawId: String? = nil,
        worktreeId: UUID,
        tmuxWindowIndex: Int = 0,
        title: String = "",
        activePaneId: String? = nil,
        paneCount: Int = 1,
        cwd: String? = nil,
        commandSummary: String? = nil,
        hasUnreadOutput: Bool = false,
        lastOutputAt: Date? = nil,
        badge: WindowBadge? = nil,
        tag: WindowTag? = nil,
        lastExitCode: Int? = nil,
        isRunning: Bool = false,
        isLongRunning: Bool = false,
        agentState: AgentState = .none,
        detectedAgent: String? = nil
    ) {
        self.tmuxWindowId = tmuxWindowId
        self.tmuxWindowRawId = tmuxWindowRawId
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
        self.tag = tag
        self.lastExitCode = lastExitCode
        self.isRunning = isRunning
        self.isLongRunning = isLongRunning
        self.agentState = agentState
        self.detectedAgent = detectedAgent
    }
}
