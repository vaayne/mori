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

            process.terminationHandler = { proc in
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: (String(data: data, encoding: .utf8) ?? "", proc.terminationStatus))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}
