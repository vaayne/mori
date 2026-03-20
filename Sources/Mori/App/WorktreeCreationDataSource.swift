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

/// Section types for branch grouping.
enum BranchSection: Sendable {
    case createNew
    case local
    case remote
}

/// A single row in the branch table — either a section header or a branch entry.
enum BranchRow: Sendable, Equatable {
    case sectionHeader(BranchSection)
    case createNewBranch(name: String)
    case branch(GitBranchInfo, inUse: Bool)

    var isSectionHeader: Bool {
        if case .sectionHeader = self { return true }
        return false
    }

    static func == (lhs: BranchRow, rhs: BranchRow) -> Bool {
        switch (lhs, rhs) {
        case (.sectionHeader(let a), .sectionHeader(let b)):
            return a == b
        case (.createNewBranch(let a), .createNewBranch(let b)):
            return a == b
        case (.branch(let a, let aInUse), .branch(let b, let bInUse)):
            return a == b && aInUse == bInUse
        default:
            return false
        }
    }
}

extension BranchSection: Equatable {}

// MARK: - DataSource

/// Pure logic for the worktree creation panel: branch filtering, section grouping,
/// and "already in use" marking. No UI dependencies — testable independently.
final class WorktreeCreationDataSource: Sendable {

    /// All branches fetched from git.
    private let allBranches: [GitBranchInfo]

    /// Branch names already used by existing worktrees (for "in use" marking).
    private let existingBranchNames: Set<String>

    init(branches: [GitBranchInfo], existingBranchNames: Set<String>) {
        self.allBranches = branches
        self.existingBranchNames = existingBranchNames
    }

    /// Filter and group branches by query. Returns rows with section headers.
    ///
    /// Sections (in order):
    /// 1. **Create New** — shown when query is non-empty and doesn't exactly match an existing branch
    /// 2. **Local** — local branches matching the query
    /// 3. **Remote** — remote branches matching the query (excluding those with a local counterpart)
    func filteredRows(query: String) -> [BranchRow] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let lowerQuery = trimmed.lowercased()

        // Separate local and remote branches
        let localBranches = allBranches.filter { !$0.isRemote }
        let remoteBranches = deduplicatedRemoteBranches()

        // Filter by query (substring, case-insensitive)
        let matchedLocal: [GitBranchInfo]
        let matchedRemote: [GitBranchInfo]

        if lowerQuery.isEmpty {
            matchedLocal = localBranches
            matchedRemote = remoteBranches
        } else {
            matchedLocal = localBranches.filter {
                $0.name.lowercased().contains(lowerQuery)
            }
            matchedRemote = remoteBranches.filter {
                $0.displayName.lowercased().contains(lowerQuery)
            }
        }

        // Determine if "Create New" should appear:
        // Query is non-empty AND doesn't exactly match any existing branch name
        let exactMatchExists = allBranches.contains { branch in
            let name = branch.isRemote ? branch.displayName : branch.name
            return name.lowercased() == lowerQuery
        }
        let showCreateNew = !trimmed.isEmpty && !exactMatchExists

        // Build rows
        var rows: [BranchRow] = []

        if showCreateNew {
            rows.append(.sectionHeader(.createNew))
            rows.append(.createNewBranch(name: trimmed))
        }

        if !matchedLocal.isEmpty {
            rows.append(.sectionHeader(.local))
            for branch in matchedLocal {
                rows.append(.branch(branch, inUse: isBranchInUse(branch)))
            }
        }

        if !matchedRemote.isEmpty {
            rows.append(.sectionHeader(.remote))
            for branch in matchedRemote {
                rows.append(.branch(branch, inUse: isBranchInUse(branch)))
            }
        }

        return rows
    }

    /// The default base branch — first local branch named "main" or "master", or the HEAD branch.
    var defaultBaseBranch: String {
        let locals = allBranches.filter { !$0.isRemote }
        if let main = locals.first(where: { $0.name == "main" }) {
            return main.name
        }
        if let master = locals.first(where: { $0.name == "master" }) {
            return master.name
        }
        if let head = locals.first(where: { $0.isHead }) {
            return head.name
        }
        return locals.first?.name ?? "main"
    }

    /// Generate a preview path for a worktree.
    static func previewPath(projectName: String, branchName: String) -> String {
        let projectSlug = slugify(projectName)
        let branchSlug = slugify(branchName)
        return "~/.mori/\(projectSlug)/\(branchSlug)"
    }

    // MARK: - Private

    /// Remote branches that don't have a local counterpart.
    private func deduplicatedRemoteBranches() -> [GitBranchInfo] {
        let localNames = Set(allBranches.filter { !$0.isRemote }.map { $0.name })
        return allBranches.filter { $0.isRemote && !localNames.contains($0.displayName) }
    }

    /// Check if a branch is already used by an existing worktree.
    private func isBranchInUse(_ branch: GitBranchInfo) -> Bool {
        let name = branch.isRemote ? branch.displayName : branch.name
        return existingBranchNames.contains(name)
    }

    /// Simple slug generation for path preview (matches SessionNaming.slugify pattern).
    private static func slugify(_ input: String) -> String {
        let lowered = input.lowercased()
        var result = ""
        var lastWasHyphen = false
        for char in lowered {
            if char.isLetter || char.isNumber {
                result.append(char)
                lastWasHyphen = false
            } else if !lastWasHyphen {
                result.append("-")
                lastWasHyphen = true
            }
        }
        // Trim leading/trailing hyphens
        while result.hasPrefix("-") { result.removeFirst() }
        while result.hasSuffix("-") { result.removeLast() }
        return result
    }
}
