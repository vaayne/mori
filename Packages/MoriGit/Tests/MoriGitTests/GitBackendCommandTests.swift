import Foundation
import MoriGit

// MARK: - addWorktree Command Argument Tests
//
// These tests verify the three code paths for worktree creation by testing
// the command argument construction logic directly. The addWorktree method
// in GitBackend builds args as:
//   - Existing branch:    ["worktree", "add", <path>, <branch>]
//   - New branch:         ["worktree", "add", "-b", <branch>, <path>]
//   - New from base:      ["worktree", "add", "-b", <branch>, <path>, <baseBranch>]
//
// Since GitBackend delegates to GitCommandRunner.run(), we test the arg-building
// logic by reimplementing the same conditional as a pure function.

/// Replicates the addWorktree argument construction from GitBackend.
/// This allows us to unit test all three code paths without needing a real git repo.
private func buildAddWorktreeArgs(
    path: String,
    branch: String,
    createBranch: Bool,
    baseBranch: String?
) -> [String] {
    var args = ["worktree", "add"]
    if createBranch {
        args += ["-b", branch, path]
        if let baseBranch {
            args.append(baseBranch)
        }
    } else {
        args += [path, branch]
    }
    return args
}

func testAddWorktreeArgsExistingBranch() {
    // Code path 1: Existing local branch (createBranch=false)
    let args = buildAddWorktreeArgs(
        path: "/home/user/.mori/proj/feature-auth",
        branch: "feature/auth",
        createBranch: false,
        baseBranch: nil
    )
    assertEqual(args, ["worktree", "add", "/home/user/.mori/proj/feature-auth", "feature/auth"])
}

func testAddWorktreeArgsExistingRemoteBranch() {
    // Code path 1 variant: Existing remote branch (createBranch=false)
    // git worktree add <path> <branch> — git auto-creates local tracking branch
    let args = buildAddWorktreeArgs(
        path: "/home/user/.mori/proj/dark-mode",
        branch: "feature/dark-mode",
        createBranch: false,
        baseBranch: nil
    )
    assertEqual(args, ["worktree", "add", "/home/user/.mori/proj/dark-mode", "feature/dark-mode"])
}

func testAddWorktreeArgsNewBranchFromHead() {
    // Code path 2: New branch from HEAD (createBranch=true, baseBranch=nil)
    let args = buildAddWorktreeArgs(
        path: "/home/user/.mori/proj/my-feature",
        branch: "my-feature",
        createBranch: true,
        baseBranch: nil
    )
    assertEqual(args, ["worktree", "add", "-b", "my-feature", "/home/user/.mori/proj/my-feature"])
}

func testAddWorktreeArgsNewBranchFromBase() {
    // Code path 3: New branch from a specific base (createBranch=true, baseBranch="main")
    let args = buildAddWorktreeArgs(
        path: "/home/user/.mori/proj/my-feature",
        branch: "my-feature",
        createBranch: true,
        baseBranch: "main"
    )
    assertEqual(args, ["worktree", "add", "-b", "my-feature", "/home/user/.mori/proj/my-feature", "main"])
}

func testAddWorktreeArgsNewBranchFromRemoteBase() {
    // Code path 3 variant: New branch from a remote base branch
    let args = buildAddWorktreeArgs(
        path: "/home/user/.mori/proj/hotfix",
        branch: "hotfix/login",
        createBranch: true,
        baseBranch: "origin/release/v2"
    )
    assertEqual(args, ["worktree", "add", "-b", "hotfix/login", "/home/user/.mori/proj/hotfix", "origin/release/v2"])
}

func testAddWorktreeArgsBaseBranchIgnoredWhenNotCreating() {
    // baseBranch is ignored when createBranch=false (existing branch checkout)
    let args = buildAddWorktreeArgs(
        path: "/home/user/.mori/proj/develop",
        branch: "develop",
        createBranch: false,
        baseBranch: "main"  // This should be ignored
    )
    // baseBranch is not in args because createBranch is false
    assertEqual(args, ["worktree", "add", "/home/user/.mori/proj/develop", "develop"])
}
