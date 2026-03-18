import Foundation
import GRDB
import MoriCore

/// GRDB record for persisting UIState as a singleton row.
public struct UIStateRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "uiState"

    public var id: Int = 1  // singleton
    public var selectedProjectId: String?
    public var selectedWorktreeId: String?
    public var selectedWindowId: String?
    public var sidebarMode: String
    public var searchQuery: String

    public init(from state: UIState) {
        self.selectedProjectId = state.selectedProjectId?.uuidString
        self.selectedWorktreeId = state.selectedWorktreeId?.uuidString
        self.selectedWindowId = state.selectedWindowId
        self.sidebarMode = state.sidebarMode.rawValue
        self.searchQuery = state.searchQuery
    }

    public func toModel() -> UIState? {
        guard let mode = SidebarMode(rawValue: sidebarMode) else {
            return nil
        }
        return UIState(
            selectedProjectId: selectedProjectId.flatMap { UUID(uuidString: $0) },
            selectedWorktreeId: selectedWorktreeId.flatMap { UUID(uuidString: $0) },
            selectedWindowId: selectedWindowId,
            sidebarMode: mode,
            searchQuery: searchQuery
        )
    }
}
