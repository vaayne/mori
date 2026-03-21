import Foundation

/// Parses output from `git branch -a --sort=-committerdate --format=...` using a `\t` (tab) delimiter.
///
/// The format string uses tab separators to avoid conflicts with `|` which is valid
/// in git ref names (e.g., `feat|pipe`). Each line has tab-delimited fields:
/// ```
/// main\t*\t1710900000\torigin/main
/// feature/auth\t\t1710800000\torigin/feature/auth
/// origin/feature/dark-mode\t\t1710700000\t
/// ```
///
/// Local branches have no `origin/` prefix and may have `*` for HEAD.
/// Remote branches start with `origin/` (or other remote name) and HEAD field is always empty.
public enum GitBranchParser {

    /// The delimiter used in the git format string. Tab is safe because git ref names
    /// cannot contain tabs (see `git-check-ref-format`).
    static let delimiter: Character = "\t"

    /// Parse the full output of `git branch -a --sort=-committerdate --format=...`.
    ///
    /// - Parameters:
    ///   - output: Raw output from `git branch -a --format=...`.
    ///   - remoteNames: Known remote names (e.g., `["origin", "upstream"]`).
    ///     Used to distinguish remote branches (e.g., `origin/main`) from local
    ///     branches with slashes (e.g., `feature/auth`). Defaults to `["origin"]`.
    public static func parse(_ output: String, remoteNames: Set<String> = ["origin"]) -> [GitBranchInfo] {
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        return output
            .components(separatedBy: "\n")
            .compactMap { line in
                parseLine(line, remoteNames: remoteNames)
            }
    }

    // MARK: - Private

    /// Parse a single line into a GitBranchInfo.
    private static func parseLine(_ line: String, remoteNames: Set<String>) -> GitBranchInfo? {
        // Only trim spaces (not tabs) since tab is our field delimiter
        let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: " "))
        guard !trimmed.isEmpty else { return nil }

        let fields = trimmed.split(separator: delimiter, omittingEmptySubsequences: false).map(String.init)
        // Must have at least the name field
        guard !fields.isEmpty, !fields[0].isEmpty else { return nil }

        let name = fields[0]

        // Filter out remote HEAD symrefs (e.g., "origin" which is origin/HEAD shortened).
        // These show up as a bare remote name with no slash after it.
        if remoteNames.contains(name) {
            return nil
        }

        let headMarker = fields.count > 1 ? fields[1] : ""
        let dateString = fields.count > 2 ? fields[2] : ""
        let upstream = fields.count > 3 ? fields[3] : ""

        let isRemote = isRemoteBranch(name, remoteNames: remoteNames)
        let isHead = headMarker == "*"

        let commitDate: Date?
        if let timestamp = TimeInterval(dateString), timestamp > 0 {
            commitDate = Date(timeIntervalSince1970: timestamp)
        } else {
            commitDate = nil
        }

        let trackingBranch: String? = upstream.isEmpty ? nil : upstream

        return GitBranchInfo(
            name: name,
            isRemote: isRemote,
            commitDate: commitDate,
            isHead: isHead,
            trackingBranch: trackingBranch
        )
    }

    /// Determine if a branch name represents a remote-tracking branch.
    ///
    /// Remote branches from `git branch -a --format='%(refname:short)'` output as
    /// `origin/branchname`. Local branches with slashes (e.g., `feature/auth`) are NOT remote.
    /// We check if the first path component matches a known remote name.
    private static func isRemoteBranch(_ name: String, remoteNames: Set<String>) -> Bool {
        guard let slashIndex = name.firstIndex(of: "/") else {
            return false
        }
        let prefix = String(name[..<slashIndex])
        return remoteNames.contains(prefix)
    }
}
