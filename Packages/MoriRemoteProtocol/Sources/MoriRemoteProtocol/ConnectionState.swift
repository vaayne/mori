import Foundation

/// State machine for relay connection lifecycle.
public enum ConnectionState: Sendable, Equatable {
    case disconnected
    case pairing
    case connected
    case attached(sessionName: String)
    case detached

    /// Valid transitions from the current state.
    public var validTransitions: Set<TransitionTarget> {
        switch self {
        case .disconnected: [.pairing, .connected]
        case .pairing: [.connected, .disconnected]
        case .connected: [.attached, .disconnected]
        case .attached: [.detached, .disconnected]
        case .detached: [.attached, .connected, .disconnected]
        }
    }

    /// Transition targets (simplified for set membership).
    public enum TransitionTarget: Sendable, Hashable {
        case disconnected, pairing, connected, attached, detached
    }

    var target: TransitionTarget {
        switch self {
        case .disconnected: .disconnected
        case .pairing: .pairing
        case .connected: .connected
        case .attached: .attached
        case .detached: .detached
        }
    }

    /// Attempt a state transition. Returns the new state if valid, nil if not.
    public func transition(to newState: ConnectionState) -> ConnectionState? {
        guard validTransitions.contains(newState.target) else { return nil }
        return newState
    }
}
