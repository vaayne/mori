import Foundation

/// Terminal-only status vocabulary. Transport/account policy intentionally stays
/// outside the transplant until Phase 2 supplies a Mori-owned composition root.
struct TerminalDisconnectReason: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case transportIO, remoteExit, runtime, unknown }
    let kind: Kind
    let message: String
}

enum TerminalRuntimeState: Equatable, Sendable {
    case connecting
    case connected
    case disconnected(TerminalDisconnectReason)
}

enum GhosttyTerminalRuntimePhase: Equatable, Sendable {
    case idle
    case starting
    case running
    case failed(message: String, reason: TerminalDisconnectReason?)
}
