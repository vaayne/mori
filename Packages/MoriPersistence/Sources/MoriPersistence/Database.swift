import Foundation
import GRDB

public struct AppDatabase: Sendable {
    private let dbWriter: any DatabaseWriter

    public var reader: any DatabaseReader { dbWriter }
    public var writer: any DatabaseWriter { dbWriter }

    public init(_ dbWriter: any DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try migrator.migrate(dbWriter)
    }

    /// Creates an in-memory database for testing.
    public static func inMemory() throws -> AppDatabase {
        let dbQueue = try DatabaseQueue(configuration: Self.makeConfiguration())
        return try AppDatabase(dbQueue)
    }

    /// Creates a database pool at the given path with WAL mode.
    public static func onDisk(path: String) throws -> AppDatabase {
        let dbPool = try DatabasePool(
            path: path,
            configuration: Self.makeConfiguration()
        )
        return try AppDatabase(dbPool)
    }

    private static func makeConfiguration() -> Configuration {
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.prepareDatabase { db in
            db.trace { print("SQL: \($0)") }
        }
        return config
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1_createProjects") { db in
            try db.create(table: "project") { t in
                t.primaryKey("id", .text).notNull()
                t.column("name", .text).notNull()
                t.column("repoRootPath", .text).notNull()
                t.column("gitCommonDir", .text).notNull().defaults(to: "")
                t.column("originURL", .text)
                t.column("iconName", .text)
                t.column("isFavorite", .boolean).notNull().defaults(to: false)
                t.column("isCollapsed", .boolean).notNull().defaults(to: false)
                t.column("lastActiveAt", .datetime)
                t.column("aggregateUnreadCount", .integer).notNull().defaults(to: 0)
                t.column("aggregateAlertState", .text).notNull().defaults(to: "none")
            }
        }

        migrator.registerMigration("v1_createWorktrees") { db in
            try db.create(table: "worktree") { t in
                t.primaryKey("id", .text).notNull()
                t.column("projectId", .text).notNull()
                    .references("project", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("path", .text).notNull()
                t.column("branch", .text)
                t.column("headSHA", .text)
                t.column("isMainWorktree", .boolean).notNull().defaults(to: false)
                t.column("isDetached", .boolean).notNull().defaults(to: false)
                t.column("hasUncommittedChanges", .boolean).notNull().defaults(to: false)
                t.column("aheadCount", .integer).notNull().defaults(to: 0)
                t.column("behindCount", .integer).notNull().defaults(to: 0)
                t.column("lastActiveAt", .datetime)
                t.column("tmuxSessionId", .text)
                t.column("tmuxSessionName", .text)
                t.column("unreadCount", .integer).notNull().defaults(to: 0)
                t.column("agentState", .text).notNull().defaults(to: "none")
                t.column("status", .text).notNull().defaults(to: "active")
            }
        }

        migrator.registerMigration("v1_createUIState") { db in
            try db.create(table: "uiState") { t in
                t.primaryKey("id", .integer) // singleton row, always id = 1
                t.column("selectedProjectId", .text)
                t.column("selectedWorktreeId", .text)
                t.column("selectedWindowId", .text)
                t.column("sidebarMode", .text).notNull().defaults(to: "worktrees")
                t.column("searchQuery", .text).notNull().defaults(to: "")
            }
        }

        return migrator
    }
}
