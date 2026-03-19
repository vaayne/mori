import Foundation

/// Direction for pane navigation and resizing.
public enum PaneDirection: String, Sendable {
    case up = "U"
    case down = "D"
    case left = "L"
    case right = "R"
    case next = "next"
    case previous = "previous"

    /// The tmux `-t` target for next/previous pane selection.
    var selectTarget: String? {
        switch self {
        case .next: return "{next}"
        case .previous: return "{previous}"
        default: return nil
        }
    }
}

/// Runtime model representing a parsed tmux pane.
public struct TmuxPane: Identifiable, Equatable, Sendable {
    public var id: String { paneId }
    public let paneId: String
    public let tty: String?
    public let isActive: Bool
    public let currentPath: String?
    public let title: String?
    /// Unix timestamp (seconds since epoch) of last pane activity, from `#{pane_activity}`.
    public let lastActivity: TimeInterval?
    /// The current command running in the pane, from `#{pane_current_command}`.
    public let currentCommand: String?
    /// Unix timestamp (seconds since epoch) of when the pane's current command started, from `#{pane_start_time}`.
    public let startTime: TimeInterval?
    /// Process ID of the pane's shell process, from `#{pane_pid}`.
    public let pid: String?

    public init(
        paneId: String,
        tty: String? = nil,
        isActive: Bool = false,
        currentPath: String? = nil,
        title: String? = nil,
        lastActivity: TimeInterval? = nil,
        currentCommand: String? = nil,
        startTime: TimeInterval? = nil,
        pid: String? = nil
    ) {
        self.paneId = paneId
        self.tty = tty
        self.isActive = isActive
        self.currentPath = currentPath
        self.title = title
        self.lastActivity = lastActivity
        self.currentCommand = currentCommand
        self.startTime = startTime
        self.pid = pid
    }
}
