import Foundation
import GRDB
import MoriCore

public struct ProjectRepository: Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    // MARK: - Read

    public func fetchAll() throws -> [Project] {
        try database.reader.read { db in
            try ProjectRecord.fetchAll(db).compactMap { $0.toModel() }
        }
    }

    public func fetch(id: UUID) throws -> Project? {
        try database.reader.read { db in
            try ProjectRecord.fetchOne(db, key: id.uuidString)?.toModel()
        }
    }

    // MARK: - Write

    public func save(_ project: Project) throws {
        let record = ProjectRecord(from: project)
        try database.writer.write { db in
            try record.save(db)
        }
    }

    public func delete(id: UUID) throws {
        _ = try database.writer.write { db in
            try ProjectRecord.deleteOne(db, key: id.uuidString)
        }
    }
}
