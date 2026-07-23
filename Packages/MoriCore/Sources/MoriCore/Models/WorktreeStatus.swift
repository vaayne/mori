import Foundation

public enum WorktreeStatus: String, Codable, Sendable {
    case active
    case inactive
    case unavailable
    /// Transient optimistic state while the workspace is materialized on disk.
    /// Never persisted — records are saved only after promotion to `.active`.
    case creating
    /// Transient state while the workspace's files are removed from disk.
    /// Never persisted — the record is deleted on success, and the previous
    /// status is restored on failure.
    case deleting

    /// A transient placeholder row: no session to attach, not selectable, not
    /// polled, and never written to the store. Every guard that special-cases
    /// placeholder rows must use this so a future transient case only needs to
    /// be added here.
    public var isTransient: Bool {
        switch self {
        case .creating, .deleting: return true
        case .active, .inactive, .unavailable: return false
        }
    }

    /// Unknown raw values (a record written by a newer app version) decode as
    /// `.active` instead of throwing: `JSONStore` treats any decode failure as
    /// a corrupt store and resets it, so one unreadable status must never cost
    /// the whole database.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WorktreeStatus(rawValue: raw) ?? .active
    }
}
