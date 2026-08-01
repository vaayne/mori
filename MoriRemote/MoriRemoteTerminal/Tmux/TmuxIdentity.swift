import Foundation

/// Stable routing identity assigned by tmux. It identifies a pane within the
/// current tmux server lifetime; it does not identify a native render surface.
struct TmuxPaneID: RawRepresentable, Hashable, Comparable, Sendable,
    CustomStringConvertible, ExpressibleByIntegerLiteral
{
    let rawValue: UInt64

    init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    init(integerLiteral value: UInt64) {
        self.rawValue = value
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var description: String {
        String(rawValue)
    }
}

/// Stable routing identity assigned by tmux. It identifies a window within
/// the current tmux server lifetime; it is not a presentation identity.
struct TmuxWindowID: RawRepresentable, Hashable, Comparable, Sendable,
    CustomStringConvertible, ExpressibleByIntegerLiteral
{
    let rawValue: UInt64

    init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    init(integerLiteral value: UInt64) {
        self.rawValue = value
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var description: String {
        String(rawValue)
    }
}

/// Identity of one native Ghostty surface instance. Recreating the surface for
/// the same tmux pane creates a new value even though its `TmuxPaneID` is unchanged.
struct TerminalSurfaceInstanceID: RawRepresentable, Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    init() {
        self.rawValue = UUID()
    }
}
