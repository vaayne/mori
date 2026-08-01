import Foundation

struct GhosttyTopLevelSurface: Identifiable, Equatable {
    let id: UUID
    let name: String
    let leafIDs: [UUID]
    let focusedLeafID: UUID?

    init(
        id: UUID = UUID(),
        name: String = "",
        leafIDs: [UUID],
        focusedLeafID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.leafIDs = leafIDs
        self.focusedLeafID = focusedLeafID.flatMap { leafIDs.contains($0) ? $0 : nil }
    }

    var resolvedFocusedLeafID: UUID? {
        focusedLeafID ?? leafIDs.first
    }
}
