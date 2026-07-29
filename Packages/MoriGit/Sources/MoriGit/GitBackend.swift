import Foundation

/// The main git integration actor. Implements GitControlling by delegating
/// to GitCommandRunner for CLI execution and parsing results.
public actor GitBackend: GitControlling {

    private let runner: GitCommandRunner

    public init(runner: GitCommandRunner = GitCommandRunner()) {
        self.runner = runner
    }

    // MARK: - GitControlling

    public func listWorktrees(repoPath: String) async throws -> [GitWorktreeInfo] {
        let output = try await runner.run(in: repoPath, ["worktree", "list", "--porcelain"])
        return GitWorktreeParser.parse(output)
    }

    public func addWorktree(
        repoPath: String,
        path: String,
        branch: String,
        createBranch: Bool,
        baseBranch: String? = nil
    ) async throws {
        var args = ["worktree", "add"]
        if createBranch {
            args += ["-b", branch, path]
            if let baseBranch {
                args.append(baseBranch)
            }
        } else {
            args += [path, branch]
        }
        _ = try await runner.run(in: repoPath, args)
    }

    /// Add a detached worktree at `path`, checked out at `ref` (default HEAD).
    /// Used as the base for `gh pr checkout` in the git-worktree fallback path:
    /// the PR's local branch is created by the subsequent checkout, so this
    /// deliberately avoids binding the worktree to any named branch.
    public func addWorktreeDetached(
        repoPath: String,
        path: String,
        ref: String? = nil
    ) async throws {
        var args = ["worktree", "add", "--detach", path]
        if let ref, !ref.isEmpty {
            args.append(ref)
        }
        _ = try await runner.run(in: repoPath, args)
    }

    public func removeWorktree(
        repoPath: String,
        path: String,
        force: Bool
    ) async throws {
        var args = ["worktree", "remove"]
        if force {
            args.append("--force")
        }
        args.append(path)
        _ = try await runner.run(in: repoPath, args)
    }

    public func status(worktreePath: String) async throws -> GitStatusInfo {
        let output = try await runner.run(
            in: worktreePath,
            ["status", "--porcelain=v2", "--branch"]
        )
        return GitStatusParser.parse(output)
    }

    public func diffStat(worktreePath: String, baseRef: String? = nil) async throws -> GitDiffStat {
        guard let baseRef else {
            // Main worktree: uncommitted changes only.
            let output = try await runner.run(in: worktreePath, ["diff", "--shortstat", "HEAD"])
            return GitDiffStat.parseShortstat(output)
        }
        // Prefer the repository's default branch (origin/HEAD): the local base
        // checkout may be stale — or sitting on another feature branch entirely —
        // which would inflate the diff with changes that aren't this branch's.
        var base: String?
        var mergeBase: String?
        for candidate in ["origin/HEAD", baseRef] {
            if let output = try? await runner.run(in: worktreePath, ["merge-base", candidate, "HEAD"]) {
                base = candidate
                mergeBase = output.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        guard let base, let mergeBase else {
            throw GitError.executionFailed(
                command: "git merge-base origin/HEAD|\(baseRef) HEAD",
                exitCode: 1,
                stderr: "no merge base"
            )
        }
        // Committed lines only (merge-base..HEAD) — matches what a PR shows;
        // uncommitted work is signalled separately via hasUncommittedChanges.
        let output = try await runner.run(in: worktreePath, ["diff", "--shortstat", mergeBase, "HEAD"])
        var conflicts: Bool?
        do {
            // merge-tree (git 2.38+) probes in-memory: exit 0 = clean, 1 = conflicts.
            _ = try await runner.run(
                in: worktreePath,
                ["merge-tree", "--write-tree", "--name-only", base, "HEAD"]
            )
            conflicts = false
        } catch GitError.executionFailed(_, let exitCode, _) where exitCode == 1 {
            conflicts = true
        } catch {
            conflicts = nil
        }
        return GitDiffStat.parseShortstat(output, hasMergeConflicts: conflicts)
    }

    public func isGitRepo(path: String) async throws -> Bool {
        do {
            _ = try await runner.run(
                in: path,
                ["rev-parse", "--is-inside-work-tree"]
            )
            return true
        } catch {
            return false
        }
    }

    public func listBranches(repoPath: String) async throws -> [GitBranchInfo] {
        let format = "%(refname:short)\t%(HEAD)\t%(committerdate:unix)\t%(upstream:short)"

        async let remoteOutput = runner.run(in: repoPath, ["remote"])
        async let branchOutput = runner.run(
            in: repoPath,
            ["branch", "-a", "--sort=-committerdate", "--format=\(format)"]
        )

        let remoteNames = Set(
            (try? await remoteOutput)?
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty } ?? []
        )

        let output = try await branchOutput
        return GitBranchParser.parse(output, remoteNames: remoteNames.isEmpty ? ["origin"] : remoteNames)
    }

    /// Count commits on HEAD that are not reachable from `baseRef`
    /// (`git rev-list --count <baseRef>..HEAD`). Throws if `baseRef` can't be
    /// resolved, letting callers try another base.
    public func commitsAhead(worktreePath: String, baseRef: String) async throws -> Int {
        let output = try await runner.run(
            in: worktreePath,
            ["rev-list", "--count", "\(baseRef)..HEAD"]
        )
        return Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    public func gitCommonDir(path: String) async throws -> String {
        let output = try await runner.run(
            in: path,
            ["rev-parse", "--git-common-dir"]
        )
        let result = output.trimmingCharacters(in: .whitespacesAndNewlines)
        // If the result is relative, resolve it against the given path
        if result.hasPrefix("/") {
            return result
        }
        return (path as NSString).appendingPathComponent(result)
    }

    /// Ensure a directory exists on the same host as this backend.
    public func ensureDirectory(path: String) async throws {
        try await runner.ensureDirectory(path: path)
    }
}
