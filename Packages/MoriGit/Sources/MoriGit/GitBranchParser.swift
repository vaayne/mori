import Foundation

/// Parses output from `git branch -a --sort=-committerdate --format='%(refname:short)|%(HEAD)|%(committerdate:unix)|%(upstream:short)'`.
///
/// Each line has `|`-delimited fields:
/// ```
/// main|*|1710900000|origin/main
/// feature/auth||1710800000|origin/feature/auth
/// origin/feature/dark-mode||1710700000|
/// ```
///
/// Local branches have no `origin/` prefix and may have `*` for HEAD.
/// Remote branches start with `origin/` (or other remote name) and HEAD field is always empty.
public enum GitBranchParser {

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
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let fields = trimmed.components(separatedBy: "|")
        // Must have at least the name field
        guard !fields.isEmpty, !fields[0].isEmpty else { return nil }

        let name = fields[0]
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
