import Foundation

public struct Project: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var repoRootPath: String
    public var gitCommonDir: String
    public var originURL: String?
    public var iconName: String?
    public var isFavorite: Bool
    public var isCollapsed: Bool
    public var lastActiveAt: Date?
    public var aggregateUnreadCount: Int
    public var aggregateAlertState: AlertState

    public init(
        id: UUID = UUID(),
        name: String,
        repoRootPath: String,
        gitCommonDir: String = "",
        originURL: String? = nil,
        iconName: String? = nil,
        isFavorite: Bool = false,
        isCollapsed: Bool = false,
        lastActiveAt: Date? = nil,
        aggregateUnreadCount: Int = 0,
        aggregateAlertState: AlertState = .none
    ) {
        self.id = id
        self.name = name
        self.repoRootPath = repoRootPath
        self.gitCommonDir = gitCommonDir
        self.originURL = originURL
        self.iconName = iconName
        self.isFavorite = isFavorite
        self.isCollapsed = isCollapsed
        self.lastActiveAt = lastActiveAt
        self.aggregateUnreadCount = aggregateUnreadCount
        self.aggregateAlertState = aggregateAlertState
    }
}
