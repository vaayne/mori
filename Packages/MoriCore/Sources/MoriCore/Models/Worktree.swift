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
    public var stagedCount: Int
    public var modifiedCount: Int
    public var untrackedCount: Int
    public var hasUpstream: Bool
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
        stagedCount: Int = 0,
        modifiedCount: Int = 0,
        untrackedCount: Int = 0,
        hasUpstream: Bool = true,
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
        self.stagedCount = stagedCount
        self.modifiedCount = modifiedCount
        self.untrackedCount = untrackedCount
        self.hasUpstream = hasUpstream
        self.lastActiveAt = lastActiveAt
        self.tmuxSessionId = tmuxSessionId
        self.tmuxSessionName = tmuxSessionName
        self.unreadCount = unreadCount
        self.agentState = agentState
        self.status = status
    }

    // Custom Codable init for backwards compatibility with existing JSON
    // that may not contain the new stagedCount/modifiedCount/untrackedCount fields.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        projectId = try container.decode(UUID.self, forKey: .projectId)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        branch = try container.decodeIfPresent(String.self, forKey: .branch)
        headSHA = try container.decodeIfPresent(String.self, forKey: .headSHA)
        isMainWorktree = try container.decode(Bool.self, forKey: .isMainWorktree)
        isDetached = try container.decode(Bool.self, forKey: .isDetached)
        hasUncommittedChanges = try container.decode(Bool.self, forKey: .hasUncommittedChanges)
        aheadCount = try container.decode(Int.self, forKey: .aheadCount)
        behindCount = try container.decode(Int.self, forKey: .behindCount)
        stagedCount = try container.decodeIfPresent(Int.self, forKey: .stagedCount) ?? 0
        modifiedCount = try container.decodeIfPresent(Int.self, forKey: .modifiedCount) ?? 0
        untrackedCount = try container.decodeIfPresent(Int.self, forKey: .untrackedCount) ?? 0
        hasUpstream = try container.decodeIfPresent(Bool.self, forKey: .hasUpstream) ?? true
        lastActiveAt = try container.decodeIfPresent(Date.self, forKey: .lastActiveAt)
        tmuxSessionId = try container.decodeIfPresent(String.self, forKey: .tmuxSessionId)
        tmuxSessionName = try container.decodeIfPresent(String.self, forKey: .tmuxSessionName)
        unreadCount = try container.decode(Int.self, forKey: .unreadCount)
        agentState = try container.decode(AgentState.self, forKey: .agentState)
        status = try container.decode(WorktreeStatus.self, forKey: .status)
    }
}
