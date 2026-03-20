import Foundation
import MoriCore

public struct ProjectRepository: Sendable {
    private let store: JSONStore

    public init(store: JSONStore) {
        self.store = store
    }

    // MARK: - Read

    public func fetchAll() throws -> [Project] {
        store.data.projects.map { $0.project }
    }

    public func fetch(id: UUID) throws -> Project? {
        store.data.projects.first { $0.project.id == id }?.project
    }

    // MARK: - Write

    public func save(_ project: Project) throws {
        store.mutate { data in
            if let index = data.projects.firstIndex(where: { $0.project.id == project.id }) {
                data.projects[index].project = project
            } else {
                data.projects.append(ProjectEntry(project: project))
            }
        }
    }

    public func delete(id: UUID) throws {
        store.mutate { data in
            data.projects.removeAll { $0.project.id == id }
        }
    }
}
