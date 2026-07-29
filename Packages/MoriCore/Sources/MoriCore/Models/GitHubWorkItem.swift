import Foundation

/// A single open GitHub issue or pull request, as listed for the workspace
/// creation panel's `#` picker.
///
/// Populated from `gh issue list` / `gh pr list` (and `gh pr view` for a single
/// URL-pasted PR). Never persisted — it is volatile picker data, re-fetched each
/// time the panel opens. Mirrors `PullRequestInfo` in shape and decoding style.
public struct GitHubWorkItem: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case issue
        case pullRequest
    }

    public let kind: Kind
    public let number: Int
    public let title: String
    /// Head branch name — only meaningful for pull requests (nil for issues).
    public let headRefName: String?
    public let isDraft: Bool

    public init(
        kind: Kind,
        number: Int,
        title: String,
        headRefName: String? = nil,
        isDraft: Bool = false
    ) {
        self.kind = kind
        self.number = number
        self.title = title
        self.headRefName = headRefName
        self.isDraft = isDraft
    }

    /// Parse a JSON array emitted by
    /// `gh issue list --json number,title` or
    /// `gh pr list --json number,title,headRefName,isDraft`.
    /// Returns an empty array when the payload can't be decoded.
    public static func parse(listJSON: Data, kind: Kind) -> [GitHubWorkItem] {
        guard let dtos = try? JSONDecoder().decode([GhWorkItemDTO].self, from: listJSON) else {
            return []
        }
        return dtos.map { $0.workItem(kind: kind) }
    }

    // MARK: - URL parsing

    /// Recognize a GitHub issue/PR URL and extract its kind + number:
    /// `https://github.com/<owner>/<repo>/issues/<n>` → `(.issue, n)`
    /// `https://github.com/<owner>/<repo>/pull/<n>`   → `(.pullRequest, n)`
    /// Returns nil for anything else. Tolerant of a trailing path/query/fragment.
    public static func parseURL(_ string: String) -> (kind: Kind, number: Int)? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let host = url.host?.lowercased(),
              host == "github.com" || host == "www.github.com" else {
            return nil
        }
        // Path components: ["/", owner, repo, "issues"|"pull", number, ...]
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 4 else { return nil }
        let kindToken = parts[2].lowercased()
        let kind: Kind
        switch kindToken {
        case "issues": kind = .issue
        case "pull": kind = .pullRequest
        default: return nil
        }
        guard let number = Int(parts[3]) else { return nil }
        return (kind, number)
    }

    // MARK: - Issue branch naming

    /// Auto-generated branch name for a new-branch-from-issue workspace:
    /// `issue-<number>-<title-slug>`, where the slug is lowercase ASCII
    /// alphanumeric runs joined by `-`, trimmed to ~40 chars at a word boundary.
    /// Degrades to `issue-<number>` when the title has no usable ASCII content
    /// (e.g. CJK-only or empty titles).
    public static func issueBranchName(number: Int, title: String) -> String {
        let slug = titleSlug(title)
        return slug.isEmpty ? "issue-\(number)" : "issue-\(number)-\(slug)"
    }

    /// Lowercase ASCII-alphanumeric slug: non-alphanumeric runs collapse to a
    /// single `-`, and the result is trimmed to at most 40 characters, cutting at
    /// the last word boundary so a partial word isn't left dangling.
    static func titleSlug(_ title: String, maxLength: Int = 40) -> String {
        var result = ""
        var lastWasHyphen = false
        for char in title.lowercased() {
            if char.isASCII, char.isLetter || char.isNumber {
                result.append(char)
                lastWasHyphen = false
            } else if !result.isEmpty, !lastWasHyphen {
                result.append("-")
                lastWasHyphen = true
            }
        }
        if result.hasSuffix("-") { result.removeLast() }

        if result.count > maxLength {
            let cut = String(result.prefix(maxLength))
            if let lastHyphen = cut.lastIndex(of: "-") {
                result = String(cut[..<lastHyphen])
            } else {
                result = cut
            }
        }
        if result.hasSuffix("-") { result.removeLast() }
        return result
    }
}

// MARK: - gh JSON DTO

/// Union of the fields requested from `gh issue list` and `gh pr list` / `gh pr
/// view`. Issues have no `headRefName`/`isDraft`; both decode optionally.
private struct GhWorkItemDTO: Decodable {
    let number: Int
    let title: String
    let headRefName: String?
    let isDraft: Bool?

    func workItem(kind: GitHubWorkItem.Kind) -> GitHubWorkItem {
        GitHubWorkItem(
            kind: kind,
            number: number,
            title: title,
            headRefName: headRefName,
            isDraft: isDraft ?? false
        )
    }
}
