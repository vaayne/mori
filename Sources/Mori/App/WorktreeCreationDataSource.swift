import Foundation
import MoriGit
import MoriCore

// MARK: - Types

/// Represents a request to create a worktree from the creation panel.
struct WorktreeCreationRequest: Sendable {
    let branchName: String
    let isNewBranch: Bool
    let baseBranch: String?
    let template: SessionTemplate
}

// MARK: - DataSource

/// Pure logic for the worktree creation panel: branch filtering, exact-match detection.
/// No UI dependencies — testable independently.
final class WorktreeCreationDataSource: Sendable {

    private static let fallbackBranch = "main"

    private let allBranches: [GitBranchInfo]

    /// Local branch names, computed once at init.
    let localBranchNames: [String]

    /// The default base branch — "main", "master", HEAD branch, or first local.
    let defaultBaseBranch: String

    init(branches: [GitBranchInfo]) {
        self.allBranches = branches

        let locals = branches.filter { !$0.isRemote }
        self.localBranchNames = locals.map(\.name)

        if let main = locals.first(where: { $0.name == "main" }) {
            self.defaultBaseBranch = main.name
        } else if let master = locals.first(where: { $0.name == "master" }) {
            self.defaultBaseBranch = master.name
        } else if let head = locals.first(where: { $0.isHead }) {
            self.defaultBaseBranch = head.name
        } else {
            self.defaultBaseBranch = locals.first?.name ?? Self.fallbackBranch
        }
    }

    /// Check if a query exactly matches an existing branch name.
    func exactMatch(for query: String) -> GitBranchInfo? {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }
        return allBranches.first { branch in
            let name = branch.isRemote ? branch.displayName : branch.name
            return name.lowercased() == trimmed
        }
    }
}
