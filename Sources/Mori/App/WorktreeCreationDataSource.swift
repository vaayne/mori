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

/// A suggestion row in the autocomplete list.
struct BranchSuggestion: Sendable, Equatable {
    let info: GitBranchInfo
    let inUse: Bool
}

// MARK: - DataSource

/// Pure logic for the worktree creation panel: branch filtering, exact-match detection,
/// and "already in use" marking. No UI dependencies — testable independently.
final class WorktreeCreationDataSource: Sendable {

    private let allBranches: [GitBranchInfo]
    private let existingBranchNames: Set<String>

    init(branches: [GitBranchInfo], existingBranchNames: Set<String>) {
        self.allBranches = branches
        self.existingBranchNames = existingBranchNames
    }

    /// Filter branches by query (substring, case-insensitive).
    /// Returns a flat list of suggestions — no section headers.
    /// Remote branches that have a local counterpart are excluded.
    func filteredSuggestions(query: String) -> [BranchSuggestion] {
        let grouped = filteredGrouped(query: query)
        return grouped.local + grouped.remote
    }

    /// Filter branches by query, returning separate local and remote arrays.
    /// Remote branches that have a local counterpart are excluded.
    func filteredGrouped(query: String) -> (local: [BranchSuggestion], remote: [BranchSuggestion]) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let lowerQuery = trimmed.lowercased()

        let localBranches = allBranches.filter { !$0.isRemote }
        let remoteBranches = deduplicatedRemoteBranches()

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

        return (
            local: matchedLocal.map { BranchSuggestion(info: $0, inUse: isBranchInUse($0)) },
            remote: matchedRemote.map { BranchSuggestion(info: $0, inUse: isBranchInUse($0)) }
        )
    }

    /// Check if a query exactly matches an existing branch name.
    /// Returns the matching GitBranchInfo if found.
    func exactMatch(for query: String) -> GitBranchInfo? {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }
        return allBranches.first { branch in
            let name = branch.isRemote ? branch.displayName : branch.name
            return name.lowercased() == trimmed
        }
    }

    /// The default base branch — "main", "master", HEAD branch, or first local.
    var defaultBaseBranch: String {
        let locals = allBranches.filter { !$0.isRemote }
        if let main = locals.first(where: { $0.name == "main" }) { return main.name }
        if let master = locals.first(where: { $0.name == "master" }) { return master.name }
        if let head = locals.first(where: { $0.isHead }) { return head.name }
        return locals.first?.name ?? "main"
    }

    /// Generate a preview path for a worktree.
    static func previewPath(projectName: String, branchName: String) -> String {
        let projectSlug = slugify(projectName)
        let branchSlug = slugify(branchName)
        return "~/.mori/\(projectSlug)/\(branchSlug)"
    }

    // MARK: - Private

    private func deduplicatedRemoteBranches() -> [GitBranchInfo] {
        let localNames = Set(allBranches.filter { !$0.isRemote }.map { $0.name })
        return allBranches.filter { $0.isRemote && !localNames.contains($0.displayName) }
    }

    private func isBranchInUse(_ branch: GitBranchInfo) -> Bool {
        let name = branch.isRemote ? branch.displayName : branch.name
        return existingBranchNames.contains(name)
    }

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
        while result.hasPrefix("-") { result.removeFirst() }
        while result.hasSuffix("-") { result.removeLast() }
        return result
    }
}
