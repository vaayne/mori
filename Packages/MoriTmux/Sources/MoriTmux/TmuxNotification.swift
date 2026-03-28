import Foundation

/// Asynchronous notification from the tmux server in control mode.
///
/// Notifications are `%`-prefixed lines that arrive outside command response
/// blocks. Unknown notification types are captured as `.unknown` for forward
/// compatibility.
public enum TmuxNotification: Sendable, Equatable {
    case sessionsChanged
    case sessionChanged(sessionId: String, name: String)
    case windowAdd(windowId: String)
    case windowClose(windowId: String)
    case windowRenamed(windowId: String, name: String)
    case windowPaneChanged(windowId: String, paneId: String)
    case layoutChanged(windowId: String, layout: String)
    case exit(reason: String?)
    case unknown(String)
}
