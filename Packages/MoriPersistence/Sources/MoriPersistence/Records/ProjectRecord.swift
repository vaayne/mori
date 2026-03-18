import Foundation
import GRDB
import MoriCore

/// GRDB record for persisting Project to SQLite.
public struct ProjectRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "project"

    public var id: String
    public var name: String
    public var repoRootPath: String
    public var gitCommonDir: String
    public var originURL: String?
    public var iconName: String?
    public var isFavorite: Bool
    public var isCollapsed: Bool
    public var lastActiveAt: Date?
    public var aggregateUnreadCount: Int
    public var aggregateAlertState: String

    public init(from project: Project) {
        self.id = project.id.uuidString
        self.name = project.name
        self.repoRootPath = project.repoRootPath
        self.gitCommonDir = project.gitCommonDir
        self.originURL = project.originURL
        self.iconName = project.iconName
        self.isFavorite = project.isFavorite
        self.isCollapsed = project.isCollapsed
        self.lastActiveAt = project.lastActiveAt
        self.aggregateUnreadCount = project.aggregateUnreadCount
        self.aggregateAlertState = project.aggregateAlertState.rawValue
    }

    public func toModel() -> Project? {
        guard let uuid = UUID(uuidString: id),
              let alertState = AlertState(rawValue: aggregateAlertState) else {
            return nil
        }
        return Project(
            id: uuid,
            name: name,
            repoRootPath: repoRootPath,
            gitCommonDir: gitCommonDir,
            originURL: originURL,
            iconName: iconName,
            isFavorite: isFavorite,
            isCollapsed: isCollapsed,
            lastActiveAt: lastActiveAt,
            aggregateUnreadCount: aggregateUnreadCount,
            aggregateAlertState: alertState
        )
    }
}
