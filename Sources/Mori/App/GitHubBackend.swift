import Foundation
import MoriCore

/// Thin wrapper around the `gh` CLI for reading the pull request tied to a
/// worktree's branch. Read-only and best-effort: any failure (gh missing, no PR,
/// network/auth error) surfaces as `nil` rather than an error, since the UI
/// treats "no PR info" and "no PR" identically.
actor GitHubBackend {
    private var resolvedBinaryPath: String?

    /// Fields requested from `gh pr view --json`. Kept in sync with `PullRequestInfo.parse`.
    private static let jsonFields = "number,title,url,state,isDraft,reviewDecision,statusCheckRollup"

    /// Fields requested for the creation panel's issue/PR lists.
    private static let workItemFields = "number,title,headRefName,isDraft"

    /// Errors from write-side gh operations that must fail loudly (checkout).
    enum GitHubBackendError: Error, LocalizedError {
        case ghUnavailable
        case launchFailed
        case commandFailed(stderr: String)

        var errorDescription: String? {
            switch self {
            case .ghUnavailable:
                return .localized("GitHub CLI (gh) was not found. Install it to work from an issue or PR.")
            case .launchFailed:
                return .localized("Failed to launch the GitHub CLI (gh).")
            case .commandFailed(let stderr):
                let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return detail.isEmpty
                    ? .localized("The GitHub CLI (gh) command failed.")
                    : String(format: .localized("The GitHub CLI (gh) command failed:\n\n%@"), detail)
            }
        }
    }

    /// Fetch the PR for `branch` in the repo at `directory`. Returns nil when
    /// there is no open PR for the branch or gh is unavailable.
    func pullRequest(forBranch branch: String, directory: String) async -> PullRequestInfo? {
        guard let gh = binaryPath() else { return nil }
        let result = await run(
            gh,
            ["pr", "view", branch, "--json", Self.jsonFields],
            in: directory
        )
        guard let result, result.exitCode == 0 else { return nil }
        return PullRequestInfo.parse(jsonData: Data(result.stdout.utf8))
    }

    /// All open PRs in the repo at `directory`, keyed by head branch — one
    /// repo-wide query that covers every worktree's badge at once. Returns nil
    /// on failure (gh missing, auth, network) so callers can distinguish "fetch
    /// failed, keep existing badges" from "no open PRs" (empty map).
    func openPullRequestsByBranch(directory: String) async -> [String: PullRequestInfo]? {
        guard let gh = binaryPath() else { return nil }
        let result = await run(
            gh,
            ["pr", "list", "--json", Self.jsonFields + ",headRefName", "--limit", "100"],
            in: directory
        )
        guard let result, result.exitCode == 0 else { return nil }
        return PullRequestInfo.parseListByBranch(jsonData: Data(result.stdout.utf8))
    }

    /// List open issues in the repo at `directory` for the `#` picker.
    /// Best-effort: any failure (gh missing, no repo, auth) → empty array.
    func issues(directory: String) async -> [GitHubWorkItem] {
        guard let gh = binaryPath() else { return [] }
        let result = await run(
            gh,
            ["issue", "list", "--json", "number,title", "--limit", "50"],
            in: directory
        )
        guard let result, result.exitCode == 0 else { return [] }
        return GitHubWorkItem.parse(listJSON: Data(result.stdout.utf8), kind: .issue)
    }

    /// List open pull requests in the repo at `directory` for the `#` picker.
    /// Best-effort: any failure → empty array.
    func openPullRequests(directory: String) async -> [GitHubWorkItem] {
        guard let gh = binaryPath() else { return [] }
        let result = await run(
            gh,
            ["pr", "list", "--json", Self.workItemFields, "--limit", "50"],
            in: directory
        )
        guard let result, result.exitCode == 0 else { return [] }
        return GitHubWorkItem.parse(listJSON: Data(result.stdout.utf8), kind: .pullRequest)
    }

    /// Check out PR `number` into the git repo at `directory` (`gh pr checkout`).
    /// Unlike the read paths, this captures stderr and throws on non-zero exit so
    /// workspace creation fails loudly and rolls back the optimistic placeholder.
    func checkoutPullRequest(number: Int, directory: String) async throws {
        guard let gh = binaryPath() else { throw GitHubBackendError.ghUnavailable }
        guard let result = await runCapturingStderr(
            gh,
            ["pr", "checkout", "\(number)"],
            in: directory
        ) else {
            throw GitHubBackendError.launchFailed
        }
        guard result.exitCode == 0 else {
            throw GitHubBackendError.commandFailed(stderr: result.stderr)
        }
    }

    // MARK: - Private

    private func binaryPath() -> String? {
        if let resolvedBinaryPath { return resolvedBinaryPath }
        let path = BinaryResolver.resolve(command: "gh")
        resolvedBinaryPath = path
        return path
    }

    private func run(
        _ executablePath: String,
        _ arguments: [String],
        in directory: String
    ) async -> (stdout: String, exitCode: Int32)? {
        await withCheckedContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
            process.standardOutput = stdout
            process.standardError = FileHandle.nullDevice
            // gh must never block on a prompt; detach stdin.
            process.standardInput = FileHandle.nullDevice
            // Ensure gh resolves on PATH for any subprocesses it spawns.
            process.environment = BinaryResolver.synthesizedEnvironment()

            let stdoutDrain = PipeDrain(stdout)
            process.terminationHandler = { proc in
                continuation.resume(returning: (
                    String(data: stdoutDrain.wait(), encoding: .utf8) ?? "",
                    proc.terminationStatus
                ))
            }

            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                stdoutDrain.abandon()
                continuation.resume(returning: nil)
            }
        }
    }

    /// Like `run`, but captures stderr separately for error reporting. Used by
    /// the write path (`gh pr checkout`) where failures must surface to the user.
    private func runCapturingStderr(
        _ executablePath: String,
        _ arguments: [String],
        in directory: String
    ) async -> (stdout: String, stderr: String, exitCode: Int32)? {
        await withCheckedContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
            process.standardOutput = stdout
            process.standardError = stderr
            process.standardInput = FileHandle.nullDevice
            process.environment = BinaryResolver.synthesizedEnvironment()

            let stdoutDrain = PipeDrain(stdout)
            let stderrDrain = PipeDrain(stderr)
            process.terminationHandler = { proc in
                continuation.resume(returning: (
                    String(data: stdoutDrain.wait(), encoding: .utf8) ?? "",
                    String(data: stderrDrain.wait(), encoding: .utf8) ?? "",
                    proc.terminationStatus
                ))
            }

            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                stdoutDrain.abandon()
                stderrDrain.abandon()
                continuation.resume(returning: nil)
            }
        }
    }
}

/// Reads a subprocess pipe to EOF on a background thread while the process
/// runs. Reading only after termination deadlocks once output exceeds the 64KB
/// pipe buffer: the child blocks on write and never exits.
private final class PipeDrain: @unchecked Sendable {
    private let group = DispatchGroup()
    private let pipe: Pipe
    private var data = Data()

    init(_ pipe: Pipe) {
        self.pipe = pipe
        group.enter()
        DispatchQueue.global(qos: .utility).async { [self] in
            data = pipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
    }

    /// Blocks until EOF and returns everything read. Call after the process
    /// has terminated, when EOF is imminent. The DispatchGroup orders the
    /// write in the reader thread before the read here.
    func wait() -> Data {
        group.wait()
        return data
    }

    /// Call when the process never launched: no writer exists, so EOF would
    /// never arrive and the reader thread would block forever. Closing the
    /// write end delivers EOF.
    func abandon() {
        try? pipe.fileHandleForWriting.close()
    }
}
