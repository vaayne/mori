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
/// Runs `gitBackend.status()` + `diffStat()` for the given worktrees (the
/// caller decides which are worth polling) in small concurrent batches.
@MainActor
final class GitStatusCoordinator {
    init() {}

    /// Poll git status and diff stats for all active worktrees concurrently.
    /// Returns a map of worktreeId -> WorktreeGitSnapshot.
    /// Skips worktrees with status == .unavailable, plus .creating/.deleting
    /// rows whose path may not exist on disk (yet, or anymore).
    /// - Parameter baseRefForWorktree: the branch a worktree's diff badge compares
    ///   against (the project's default branch); nil for the main worktree, which
    ///   diffs its own uncommitted changes instead.
    func pollAll(
        worktrees: [Worktree],
        backendForWorktree: @escaping @MainActor (Worktree) -> GitBackend,
        baseRefForWorktree: @escaping @MainActor (Worktree) -> String?
    ) async -> [UUID: WorktreeGitSnapshot] {
        let activeWorktrees = worktrees.filter {
            $0.status != .unavailable && !$0.status.isTransient && $0.branch != nil
        }
        guard !activeWorktrees.isEmpty else { return [:] }
        return await withTaskGroup(of: (UUID, WorktreeGitSnapshot?).self) { group in
            var results: [UUID: WorktreeGitSnapshot] = [:]
            // Batches of `maxConcurrent`: each worktree costs two git
            // subprocesses, so an unbounded fan-out over many workspaces turns
            // every tick into a process storm.
            let maxConcurrent = 6
            for start in stride(from: 0, to: activeWorktrees.count, by: maxConcurrent) {
                let batch = activeWorktrees[start..<min(start + maxConcurrent, activeWorktrees.count)]
                for worktree in batch {
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
                for _ in batch.indices {
                    guard let (id, snapshot) = await group.next() else { break }
                    if let snapshot {
                        results[id] = snapshot
                    }
                }
            }
            return results
        }
    }
}
