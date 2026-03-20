import Foundation

/// Protocol for git operations, enabling testability via mock implementations.
/// Follows the TmuxControlling pattern.
public protocol GitControlling: Sendable {

    /// List all worktrees for a git repository.
    func listWorktrees(repoPath: String) async throws -> [GitWorktreeInfo]

    /// Add a new worktree at the given path for the specified branch.
    /// - Parameters:
    ///   - repoPath: Path to the main repository.
    ///   - path: Destination path for the new worktree.
    ///   - branch: Branch name to check out.
    ///   - createBranch: If true, creates a new branch (`-b`).
    ///   - baseBranch: When `createBranch` is true, the branch to base the new branch on.
    ///     When nil, the new branch is based on HEAD. Ignored when `createBranch` is false.
    func addWorktree(repoPath: String, path: String, branch: String, createBranch: Bool, baseBranch: String?) async throws

    /// Remove a worktree.
    /// - Parameters:
    ///   - repoPath: Path to the main repository.
    ///   - path: Path of the worktree to remove.
    ///   - force: If true, forces removal even with uncommitted changes.
    func removeWorktree(repoPath: String, path: String, force: Bool) async throws

    /// Get the current status of a worktree (dirty files, ahead/behind, branch).
    func status(worktreePath: String) async throws -> GitStatusInfo

    /// Check whether the given path is inside a git repository.
    func isGitRepo(path: String) async throws -> Bool

    /// Return the git common directory for the given path (resolves via `git rev-parse --git-common-dir`).
    /// For a main worktree this is typically `<repo>/.git`; for linked worktrees it points to the shared `.git` dir.
    func gitCommonDir(path: String) async throws -> String

    /// List all branches (local and remote) for a git repository, sorted by most recent commit.
    func listBranches(repoPath: String) async throws -> [GitBranchInfo]
}
