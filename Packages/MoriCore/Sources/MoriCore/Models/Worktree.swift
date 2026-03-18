import Foundation

public struct Worktree: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let projectId: UUID
    public var name: String
    public var path: String
    public var branch: String?
    public var headSHA: String?
    public var isMainWorktree: Bool
    public var isDetached: Bool
    public var hasUncommittedChanges: Bool
    public var aheadCount: Int
    public var behindCount: Int
    public var lastActiveAt: Date?
    public var tmuxSessionId: String?
    public var tmuxSessionName: String?
    public var unreadCount: Int
    public var agentState: AgentState
    public var status: WorktreeStatus

    public init(
        id: UUID = UUID(),
        projectId: UUID,
        name: String,
        path: String,
        branch: String? = nil,
        headSHA: String? = nil,
        isMainWorktree: Bool = false,
        isDetached: Bool = false,
        hasUncommittedChanges: Bool = false,
        aheadCount: Int = 0,
        behindCount: Int = 0,
        lastActiveAt: Date? = nil,
        tmuxSessionId: String? = nil,
        tmuxSessionName: String? = nil,
        unreadCount: Int = 0,
        agentState: AgentState = .none,
        status: WorktreeStatus = .active
    ) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.path = path
        self.branch = branch
        self.headSHA = headSHA
        self.isMainWorktree = isMainWorktree
        self.isDetached = isDetached
        self.hasUncommittedChanges = hasUncommittedChanges
        self.aheadCount = aheadCount
        self.behindCount = behindCount
        self.lastActiveAt = lastActiveAt
        self.tmuxSessionId = tmuxSessionId
        self.tmuxSessionName = tmuxSessionName
        self.unreadCount = unreadCount
        self.agentState = agentState
        self.status = status
    }
}
