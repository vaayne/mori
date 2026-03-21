import Foundation

public struct UIState: Codable, Equatable, Sendable {
    public var selectedProjectId: UUID?
    public var selectedWorktreeId: UUID?
    public var selectedWindowId: String?
    public var sidebarMode: SidebarMode
    public var searchQuery: String

    public init(
        selectedProjectId: UUID? = nil,
        selectedWorktreeId: UUID? = nil,
        selectedWindowId: String? = nil,
        sidebarMode: SidebarMode = .workspaces,
        searchQuery: String = ""
    ) {
        self.selectedProjectId = selectedProjectId
        self.selectedWorktreeId = selectedWorktreeId
        self.selectedWindowId = selectedWindowId
        self.sidebarMode = sidebarMode
        self.searchQuery = searchQuery
    }
}
