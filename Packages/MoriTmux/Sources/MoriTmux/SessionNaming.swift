import Foundation

/// Utilities for the Mori tmux session naming convention: `<project-short-name>/<branch-slug>`.
/// Uses `/` as separator for human-readable `tmux ls` output.
public enum SessionNaming {

    /// The separator between project short name and branch slug.
    public static let separator = "/"

    /// Common branch prefixes to strip for shorter names.
    private static let strippablePrefixes = [
        "feature/", "feat/", "fix/", "bugfix/", "hotfix/", "release/",
    ]

    /// Slugify a string: lowercase, replace non-alphanumeric characters with hyphens,
    /// collapse consecutive hyphens, trim leading/trailing hyphens.
    public static func slugify(_ input: String) -> String {
        let lowered = input.lowercased()
        var result = ""
        var lastWasHyphen = false
        for char in lowered {
            if char.isLetter || char.isNumber {
                result.append(char)
                lastWasHyphen = false
            } else {
                if !lastWasHyphen && !result.isEmpty {
                    result.append("-")
                    lastWasHyphen = true
                }
            }
        }
        // Trim trailing hyphen
        if result.hasSuffix("-") {
            result.removeLast()
        }
        return result
    }

    /// Strip common branch prefixes (feature/, fix/, etc.) for shorter display.
    public static func stripBranchPrefix(_ branch: String) -> String {
        let lower = branch.lowercased()
        for prefix in strippablePrefixes {
            if lower.hasPrefix(prefix) {
                return String(branch.dropFirst(prefix.count))
            }
        }
        return branch
    }

    /// Build a Mori session name from project short name and branch name.
    /// Format: `<shortName>/<branchSlug>` (e.g. `mori/main`, `api/auth-flow`).
    /// Both parts are slugified to ensure tmux compatibility (no dots, colons, etc.).
    public static func sessionName(projectShortName: String, worktree: String) -> String {
        let branch = stripBranchPrefix(worktree)
        let project = slugify(projectShortName)
        return "\(project.isEmpty ? "project" : project)\(separator)\(slugify(branch))"
    }

    /// Check if a session name matches the Mori naming convention (contains `/`).
    public static func isMoriSession(_ name: String) -> Bool {
        name.contains(separator) && parse(name) != nil
    }

    /// Parse a Mori session name into (projectShortName, branchSlug).
    /// Returns nil if the name doesn't match the convention.
    public static func parse(_ name: String) -> (projectShortName: String, branchSlug: String)? {
        guard let slashIndex = name.firstIndex(of: "/") else { return nil }
        let project = String(name[name.startIndex..<slashIndex])
        let branch = String(name[name.index(after: slashIndex)...])
        guard !project.isEmpty, !branch.isEmpty else { return nil }
        return (projectShortName: project, branchSlug: branch)
    }
}
