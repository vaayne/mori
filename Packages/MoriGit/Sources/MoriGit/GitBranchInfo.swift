import Foundation

/// Parsed information about a single git branch from `git branch -a --sort=-committerdate --format=...`.
public struct GitBranchInfo: Equatable, Sendable, Codable {
    /// The short branch name (e.g., "main", "feature/auth").
    /// For remote branches, this is the full remote ref (e.g., "origin/main").
    public let name: String

    /// Whether this is a remote-tracking branch (e.g., "origin/main").
    public let isRemote: Bool

    /// The commit date as a Unix timestamp, or nil if unavailable.
    public let commitDate: Date?

    /// Whether this branch is the current HEAD branch.
    public let isHead: Bool

    /// The upstream tracking branch (e.g., "origin/main"), or nil if none.
    public let trackingBranch: String?

    public init(
        name: String,
        isRemote: Bool = false,
        commitDate: Date? = nil,
        isHead: Bool = false,
        trackingBranch: String? = nil
    ) {
        self.name = name
        self.isRemote = isRemote
        self.commitDate = commitDate
        self.isHead = isHead
        self.trackingBranch = trackingBranch
    }

    /// The display name with remote prefix stripped (e.g., "origin/main" → "main").
    public var displayName: String {
        if isRemote, let slashIndex = name.firstIndex(of: "/") {
            return String(name[name.index(after: slashIndex)...])
        }
        return name
    }

    /// The remote name (e.g., "origin"), or nil for local branches.
    public var remoteName: String? {
        guard isRemote, let slashIndex = name.firstIndex(of: "/") else {
            return nil
        }
        return String(name[..<slashIndex])
    }
}
