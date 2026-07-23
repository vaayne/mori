import Foundation
import MoriGit


// MARK: - Types

/// Where a workspace-creation request originated. Defaults to `.branch` so the
/// plain branch-name flow and all existing call sites stay unchanged.
enum CreationOrigin: Sendable, Equatable {
    /// Ordinary branch name (new or existing).
    case branch
    /// New branch from a GitHub issue; `branchName` carries the auto-generated name.
    case issue(number: Int)
    /// Work on a GitHub PR's head branch. `headRef` must be resolved panel-side
    /// (the picker only offers prefetched PRs); the manager rejects an empty one.
    case pullRequest(number: Int, headRef: String)
}

/// Represents a request to create a worktree from the creation panel.
struct WorktreeCreationRequest: Sendable {
    /// The project the panel was showing. Carried in the request because the
    /// panel floats over an interactive main window: the globally selected
    /// project can change while it's open, and the branch/base data the user
    /// confirmed belongs to this one.
    let projectId: UUID
    let branchName: String
    let isNewBranch: Bool
    let baseBranch: String?
    let origin: CreationOrigin

    init(
        projectId: UUID,
        branchName: String,
        isNewBranch: Bool,
        baseBranch: String?,
        origin: CreationOrigin = .branch
    ) {
        self.projectId = projectId
        self.branchName = branchName
        self.isNewBranch = isNewBranch
        self.baseBranch = baseBranch
        self.origin = origin
    }
}

// MARK: - DataSource

/// Pure logic for the worktree creation panel: branch filtering, exact-match detection.
/// No UI dependencies — testable independently.
final class WorktreeCreationDataSource: Sendable {

    private static let fallbackBranch = "main"

    private let allBranches: [GitBranchInfo]

    /// Local (non-remote) branches, computed once at init.
    let localBranches: [GitBranchInfo]

    /// Local branch names, computed once at init.
    let localBranchNames: [String]

    /// The default base branch — "main", "master", HEAD branch, or first local.
    let defaultBaseBranch: String

    init(branches: [GitBranchInfo]) {
        self.allBranches = branches

        let locals = branches.filter { !$0.isRemote }
        self.localBranches = locals
        self.localBranchNames = locals.map(\.name)

        if let main = locals.first(where: { $0.name == "main" }) {
            self.defaultBaseBranch = main.name
        } else if let master = locals.first(where: { $0.name == "master" }) {
            self.defaultBaseBranch = master.name
        } else if let head = locals.first(where: { $0.isHead }) {
            self.defaultBaseBranch = head.name
        } else {
            self.defaultBaseBranch = locals.first?.name ?? Self.fallbackBranch
        }
    }

    /// Local branches available to check out: excludes any branch that already
    /// backs a workspace in the current project, then narrows by a case-insensitive
    /// substring query. An empty query keeps every non-excluded branch.
    func checkoutBranches(excluding excluded: Set<String>, matching query: String) -> [GitBranchInfo] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return localBranches.filter { branch in
            guard !excluded.contains(branch.name) else { return false }
            guard !q.isEmpty else { return true }
            return branch.name.lowercased().contains(q)
        }
    }

    /// Check if a query exactly matches an existing branch name.
    func exactMatch(for query: String) -> GitBranchInfo? {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }
        return allBranches.first { branch in
            let name = branch.isRemote ? branch.displayName : branch.name
            return name.lowercased() == trimmed
        }
    }
}
