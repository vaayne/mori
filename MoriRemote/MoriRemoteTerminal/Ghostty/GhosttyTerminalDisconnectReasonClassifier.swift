import Foundation

/// Classification is intentionally transport-agnostic until Phase 2 supplies
/// Mori's SSH adapter. No SSH/NIO type is referenced by the core target.
enum GhosttyTerminalDisconnectReasonClassifier {
    static func transportStartFailure(_ error: any Error) -> TerminalDisconnectReason {
        .init(kind: .unknown, message: String(describing: error))
    }

    static func foregroundMissingHost() -> TerminalDisconnectReason {
        .init(kind: .transportIO, message: "tmux transport unavailable after foreground")
    }
}
