import Foundation

/// Runtime model representing a parsed tmux window.
public struct TmuxWindow: Identifiable, Equatable, Sendable {
    public var id: String { windowId }
    public let windowId: String
    public let windowIndex: Int
    public let name: String
    public let isActive: Bool
    public let currentPath: String?
    public var panes: [TmuxPane]

    public init(
        windowId: String,
        windowIndex: Int = 0,
        name: String = "",
        isActive: Bool = false,
        currentPath: String? = nil,
        panes: [TmuxPane] = []
    ) {
        self.windowId = windowId
        self.windowIndex = windowIndex
        self.name = name
        self.isActive = isActive
        self.currentPath = currentPath
        self.panes = panes
    }
}
