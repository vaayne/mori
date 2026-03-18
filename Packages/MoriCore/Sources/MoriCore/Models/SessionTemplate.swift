import Foundation

/// Describes a window to create in a tmux session.
public struct WindowTemplate: Sendable, Equatable {
    /// Display name for the window.
    public let name: String
    /// Command to run in the window after creation. Nil means just open a shell.
    public let command: String?

    public init(name: String, command: String? = nil) {
        self.name = name
        self.command = command
    }
}

/// Describes a set of windows to create when initializing a tmux session.
public struct SessionTemplate: Sendable, Equatable {
    /// Human-readable template name (e.g. "basic", "go", "agent").
    public let name: String
    /// Windows to create. The first window reuses the session's default window.
    public let windows: [WindowTemplate]

    public init(name: String, windows: [WindowTemplate]) {
        self.name = name
        self.windows = windows
    }
}
