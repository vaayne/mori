import Foundation

/// Parsed information about a single git worktree from `git worktree list --porcelain`.
public struct GitWorktreeInfo: Equatable, Sendable {
    /// Absolute path to the worktree directory.
    public let path: String

    /// The HEAD commit SHA.
    public let head: String

    /// The branch ref (e.g., "refs/heads/main"), or nil if detached or bare.
    public let branch: String?

    /// Whether this worktree has a detached HEAD.
    public let isDetached: Bool

    /// Whether this is a bare repository worktree.
    public let isBare: Bool

    public init(
        path: String,
        head: String,
        branch: String? = nil,
        isDetached: Bool = false,
        isBare: Bool = false
    ) {
        self.path = path
        self.head = head
        self.branch = branch
        self.isDetached = isDetached
        self.isBare = isBare
    }

    /// The short branch name extracted from the full ref (e.g., "main" from "refs/heads/main").
    public var branchName: String? {
        guard let branch else { return nil }
        let prefix = "refs/heads/"
        if branch.hasPrefix(prefix) {
            return String(branch.dropFirst(prefix.count))
        }
        return branch
    }
}
