import Foundation

public enum WorktreeStatus: String, Codable, Sendable {
    case active
    case inactive
    case unavailable
    /// Transient optimistic state while the workspace is materialized on disk.
    /// Never persisted — records are saved only after promotion to `.active`.
    case creating
}
