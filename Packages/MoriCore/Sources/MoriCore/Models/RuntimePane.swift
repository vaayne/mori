import Foundation

public struct RuntimePane: Identifiable, Codable, Equatable, Sendable {
    public var id: String { tmuxPaneId }
    public let tmuxPaneId: String
    public let tmuxWindowId: String
    public var title: String?
    public var cwd: String?
    public var tty: String?
    public var isActive: Bool
    public var isZoomed: Bool

    public init(
        tmuxPaneId: String,
        tmuxWindowId: String,
        title: String? = nil,
        cwd: String? = nil,
        tty: String? = nil,
        isActive: Bool = false,
        isZoomed: Bool = false
    ) {
        self.tmuxPaneId = tmuxPaneId
        self.tmuxWindowId = tmuxWindowId
        self.title = title
        self.cwd = cwd
        self.tty = tty
        self.isActive = isActive
        self.isZoomed = isZoomed
    }
}
