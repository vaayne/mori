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

/// Owns the reversible identity boundary between tmux's typed numeric IDs and
/// the UUIDs used by terminal presentation projections.
struct TmuxTerminalIdentityRegistry {
    private var paneSurfaceIDsByTmuxID: [TmuxPaneID: UUID] = [:]
    private var paneTmuxIDsBySurfaceID: [UUID: TmuxPaneID] = [:]
    private var windowSurfaceIDsByTmuxID: [TmuxWindowID: UUID] = [:]
    private var windowTmuxIDsBySurfaceID: [UUID: TmuxWindowID] = [:]

    mutating func surfaceID(for paneID: TmuxPaneID) -> UUID {
        if let existing = paneSurfaceIDsByTmuxID[paneID] {
            return existing
        }

        let surfaceID = UUID()
        paneSurfaceIDsByTmuxID[paneID] = surfaceID
        paneTmuxIDsBySurfaceID[surfaceID] = paneID
        return surfaceID
    }

    func paneID(for surfaceID: UUID) -> TmuxPaneID? {
        paneTmuxIDsBySurfaceID[surfaceID]
    }

    mutating func surfaceID(for windowID: TmuxWindowID) -> UUID {
        if let existing = windowSurfaceIDsByTmuxID[windowID] {
            return existing
        }

        let surfaceID = UUID()
        windowSurfaceIDsByTmuxID[windowID] = surfaceID
        windowTmuxIDsBySurfaceID[surfaceID] = windowID
        return surfaceID
    }

    func windowID(for surfaceID: UUID) -> TmuxWindowID? {
        windowTmuxIDsBySurfaceID[surfaceID]
    }
}
