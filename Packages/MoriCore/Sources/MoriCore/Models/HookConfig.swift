import Foundation

/// Lifecycle events that can trigger hooks.
public enum HookEvent: String, Codable, Sendable, Equatable {
    case onWorktreeCreate
    case onWorktreeFocus
    case onWorktreeClose
    case onWindowCreate
    case onWindowFocus
    case onWindowClose
}

/// An action to perform when a hook event fires.
/// At least one of `shell` or `tmuxSend` should be non-nil.
public struct HookAction: Codable, Sendable, Equatable {
    /// Shell command to run via /bin/zsh -c.
    public let shell: String?
    /// Keys to send to the active tmux pane.
    public let tmuxSend: String?

    public init(shell: String? = nil, tmuxSend: String? = nil) {
        self.shell = shell
        self.tmuxSend = tmuxSend
    }
}

/// A single hook entry binding an event to one or more actions.
public struct HookEntry: Codable, Sendable, Equatable {
    public let event: HookEvent
    public let actions: [HookAction]

    public init(event: HookEvent, actions: [HookAction]) {
        self.event = event
        self.actions = actions
    }
}

/// Per-project hook configuration, loaded from `.mori/hooks.json`.
public struct HookConfig: Codable, Sendable, Equatable {
    public let hooks: [HookEntry]

    public init(hooks: [HookEntry] = []) {
        self.hooks = hooks
    }

    /// Return all actions for a given event.
    public func actions(for event: HookEvent) -> [HookAction] {
        hooks.filter { $0.event == event }.flatMap { $0.actions }
    }
}
