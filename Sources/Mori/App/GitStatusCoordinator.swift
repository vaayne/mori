import Foundation
import MoriCore
import MoriGit

/// One poll cycle's git view of a worktree: porcelain status plus the
/// line-level diff/conflict probe against the project's base branch.
struct WorktreeGitSnapshot: Sendable {
    let status: GitStatusInfo
    let diff: GitDiffStat?
}

/// Encapsulates git status polling logic.
/// Runs `gitBackend.status()` + `diffStat()` concurrently for all active worktrees via TaskGroup.
@MainActor
final class GitStatusCoordinator {
    init() {}

    /// Poll git status and diff stats for all active worktrees concurrently.
    /// Returns a map of worktreeId -> WorktreeGitSnapshot.
    /// Skips worktrees with status == .unavailable.
    /// - Parameter baseRefForWorktree: the branch a worktree's diff badge compares
    ///   against (the project's default branch); nil for the main worktree, which
    ///   diffs its own uncommitted changes instead.
    func pollAll(
        worktrees: [Worktree],
        backendForWorktree: @escaping @MainActor (Worktree) -> GitBackend,
        baseRefForWorktree: @escaping @MainActor (Worktree) -> String?
    ) async -> [UUID: WorktreeGitSnapshot] {
        let activeWorktrees = worktrees.filter { $0.status != .unavailable && $0.branch != nil }
        guard !activeWorktrees.isEmpty else { return [:] }
        return await withTaskGroup(of: (UUID, WorktreeGitSnapshot?).self) { group in
            for worktree in activeWorktrees {
                let backend = backendForWorktree(worktree)
                let baseRef = baseRefForWorktree(worktree)
                group.addTask {
                    do {
                        let status = try await backend.status(worktreePath: worktree.path)
                        // Diff failures (e.g. no merge-base yet) shouldn't drop the status.
                        let diff = try? await backend.diffStat(worktreePath: worktree.path, baseRef: baseRef)
                        return (worktree.id, WorktreeGitSnapshot(status: status, diff: diff))
                    } catch {
                        return (worktree.id, nil)
                    }
                }
            }

            var results: [UUID: WorktreeGitSnapshot] = [:]
            for await (id, snapshot) in group {
                if let snapshot {
                    results[id] = snapshot
                }
            }
            return results
        }
    }
}
