import Foundation

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
