import Foundation

struct GhosttyTopLevelSurface: Identifiable, Equatable {
    let id: UUID
    let leafIDs: [UUID]
    let focusedLeafID: UUID?

    init(
        id: UUID = UUID(),
        leafIDs: [UUID],
        focusedLeafID: UUID? = nil
    ) {
        self.id = id
        self.leafIDs = leafIDs
        self.focusedLeafID = focusedLeafID.flatMap { leafIDs.contains($0) ? $0 : nil }
    }

    var resolvedFocusedLeafID: UUID? {
        focusedLeafID ?? leafIDs.first
    }
}
