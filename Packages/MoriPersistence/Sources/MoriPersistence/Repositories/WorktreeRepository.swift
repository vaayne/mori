import Foundation
import GRDB
import MoriCore

public struct WorktreeRepository: Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    // MARK: - Read

    public func fetchAll(forProject projectId: UUID) throws -> [Worktree] {
        try database.reader.read { db in
            try WorktreeRecord
                .filter(Column("projectId") == projectId.uuidString)
                .fetchAll(db)
                .compactMap { $0.toModel() }
        }
    }

    public func fetch(id: UUID) throws -> Worktree? {
        try database.reader.read { db in
            try WorktreeRecord.fetchOne(db, key: id.uuidString)?.toModel()
        }
    }

    // MARK: - Write

    public func save(_ worktree: Worktree) throws {
        let record = WorktreeRecord(from: worktree)
        try database.writer.write { db in
            try record.save(db)
        }
    }

    public func delete(id: UUID) throws {
        _ = try database.writer.write { db in
            try WorktreeRecord.deleteOne(db, key: id.uuidString)
        }
    }
}
