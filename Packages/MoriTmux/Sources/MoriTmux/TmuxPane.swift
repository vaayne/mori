import Foundation

/// Runtime model representing a parsed tmux pane.
public struct TmuxPane: Identifiable, Equatable, Sendable {
    public var id: String { paneId }
    public let paneId: String
    public let tty: String?
    public let isActive: Bool
    public let currentPath: String?
    public let title: String?

    public init(
        paneId: String,
        tty: String? = nil,
        isActive: Bool = false,
        currentPath: String? = nil,
        title: String? = nil
    ) {
        self.paneId = paneId
        self.tty = tty
        self.isActive = isActive
        self.currentPath = currentPath
        self.title = title
    }
}
