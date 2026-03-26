import Foundation

/// Errors that can occur when running git commands.
public enum GitError: Error, LocalizedError, Sendable {
    case binaryNotFound
    case executionFailed(command: String, exitCode: Int32, stderr: String)
    case notAGitRepo(path: String)
    case worktreeAlreadyExists(path: String)
    case parseError(String)

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "git binary not found. Install git and ensure it is on PATH."
        case .executionFailed(let command, let exitCode, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return "git failed (exit \(exitCode)): \(command)"
            }
            return "git failed (exit \(exitCode)): \(detail)"
        case .notAGitRepo(let path):
            return "\"\(path)\" is not a git repository."
        case .worktreeAlreadyExists(let path):
            return "A worktree already exists at \"\(path)\"."
        case .parseError(let message):
            return "Failed to parse git output: \(message)"
        }
    }
}
