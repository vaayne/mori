import Foundation

enum GhosttyTmuxActionMissingTarget: Equatable, Sendable {
    case host
    case pane(UUID)
    case focusedPane
    case window(UUID)
    case windowPane(UUID)
    case selectedWindow
    case adjacentWindow
}

