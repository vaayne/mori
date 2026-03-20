import Foundation
import MoriCore

public struct WorktreeRepository: Sendable {
    private let store: JSONStore

    public init(store: JSONStore) {
        self.store = store
    }

    // MARK: - Read

    public func fetchAll(forProject projectId: UUID) throws -> [Worktree] {
        store.data.projects.first { $0.project.id == projectId }?.worktrees ?? []
    }

    public func fetch(id: UUID) throws -> Worktree? {
        for entry in store.data.projects {
            if let wt = entry.worktrees.first(where: { $0.id == id }) {
                return wt
            }
        }
        return nil
    }

    // MARK: - Write

    public func save(_ worktree: Worktree) throws {
        store.mutate { data in
            guard let pi = data.projects.firstIndex(where: { $0.project.id == worktree.projectId }) else { return }
            if let wi = data.projects[pi].worktrees.firstIndex(where: { $0.id == worktree.id }) {
                data.projects[pi].worktrees[wi] = worktree
            } else {
                data.projects[pi].worktrees.append(worktree)
            }
        }
    }

    public func delete(id: UUID) throws {
        store.mutate { data in
            for pi in data.projects.indices {
                data.projects[pi].worktrees.removeAll { $0.id == id }
            }
        }
    }
}
