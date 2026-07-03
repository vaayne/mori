import Foundation

/// Line-level diff summary of a worktree against its base branch,
/// from `git diff --shortstat` plus an optional `git merge-tree` conflict probe.
public struct GitDiffStat: Equatable, Sendable {
    /// Lines added relative to the merge-base with the base branch
    /// (includes uncommitted changes; untracked files are not counted).
    public let additions: Int

    /// Lines removed relative to the merge-base with the base branch.
    public let deletions: Int

    /// Whether merging this branch into the base would conflict.
    /// nil when the probe was skipped or failed (e.g. git < 2.38).
    public let hasMergeConflicts: Bool?

    public init(additions: Int = 0, deletions: Int = 0, hasMergeConflicts: Bool? = nil) {
        self.additions = additions
        self.deletions = deletions
        self.hasMergeConflicts = hasMergeConflicts
    }

    /// Parse `git diff --shortstat` output, e.g.
    /// ` 3 files changed, 312 insertions(+), 332 deletions(-)`.
    /// Empty output (no changes) parses to zeros.
    public static func parseShortstat(_ output: String, hasMergeConflicts: Bool? = nil) -> GitDiffStat {
        var additions = 0
        var deletions = 0
        for part in output.split(separator: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let count = Int(trimmed.prefix(while: \.isNumber)) else { continue }
            if trimmed.contains("insertion") { additions = count }
            if trimmed.contains("deletion") { deletions = count }
        }
        return GitDiffStat(additions: additions, deletions: deletions, hasMergeConflicts: hasMergeConflicts)
    }
}
