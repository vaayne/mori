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
}
