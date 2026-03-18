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
        createBranch: Bool
    ) async throws {
        var args = ["worktree", "add"]
        if createBranch {
            args += ["-b", branch, path]
        } else {
            args += [path, branch]
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
}
