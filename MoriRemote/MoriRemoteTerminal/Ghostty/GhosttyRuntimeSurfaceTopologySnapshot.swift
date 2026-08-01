import Foundation

struct GhosttyRuntimeSurfaceTopologySnapshot: Equatable {
    static var empty: GhosttyRuntimeSurfaceTopologySnapshot {
        GhosttyRuntimeSurfaceTopologySnapshot(
            topLevels: [],
            selectedTopLevelID: nil
        )
    }

    let topLevels: [GhosttyTopLevelSurface]
    let selectedTopLevelID: UUID?
    let selectedTopLevel: GhosttyTopLevelSurface?
    let selectedTopLevelIndex: Int?

    init(
        topLevels: [GhosttyTopLevelSurface],
        selectedTopLevelID: UUID?
    ) {
        self.topLevels = topLevels
        self.selectedTopLevelID = selectedTopLevelID

        guard let selectedTopLevelID,
              let selectedTopLevelIndex = topLevels.firstIndex(where: { $0.id == selectedTopLevelID })
        else {
            self.selectedTopLevel = nil
            self.selectedTopLevelIndex = nil
            return
        }

        let selectedTopLevel = topLevels[selectedTopLevelIndex]

        self.selectedTopLevel = selectedTopLevel
        self.selectedTopLevelIndex = selectedTopLevelIndex
    }
}
