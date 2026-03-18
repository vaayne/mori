import Foundation

/// Utilities for the Mori tmux session naming convention: `ws::<project-slug>::<worktree-slug>`.
public enum SessionNaming {

    /// The prefix used for all Mori-managed tmux sessions.
    public static let prefix = "ws::"

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

    /// Build a Mori session name from project and worktree names.
    public static func sessionName(project: String, worktree: String) -> String {
        "\(prefix)\(slugify(project))::\(slugify(worktree))"
    }

    /// Check if a session name matches the Mori naming convention.
    public static func isMoriSession(_ name: String) -> Bool {
        name.hasPrefix(prefix)
    }

    /// Parse a Mori session name into (projectSlug, worktreeSlug).
    /// Returns nil if the name doesn't match the convention.
    public static func parse(_ name: String) -> (projectSlug: String, worktreeSlug: String)? {
        guard isMoriSession(name) else { return nil }
        let withoutPrefix = String(name.dropFirst(prefix.count))
        let parts = withoutPrefix.split(separator: "::", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        return (projectSlug: String(parts[0]), worktreeSlug: String(parts[1]))
    }
}
