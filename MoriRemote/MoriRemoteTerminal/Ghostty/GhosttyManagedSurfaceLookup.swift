import Foundation

@MainActor
struct GhosttyManagedSurfaceLookup {
    static let empty = GhosttyManagedSurfaceLookup { _ in nil }

    private let lookup: (UUID) -> GhosttyManagedSurface?

    init(_ lookup: @escaping (UUID) -> GhosttyManagedSurface?) {
        self.lookup = lookup
    }

    func managedSurface(for id: UUID) -> GhosttyManagedSurface? {
        lookup(id)
    }
}
