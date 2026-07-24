import Foundation

/// A branch as the workspace picker sees it — a value snapshot of the git
/// branch list, decoupled from MoriGit so this model (and its tests) stay in
/// MoriCore next to `GitHubWorkItem`.
public struct PickerBranch: Sendable, Equatable {
    /// Short name; for remote branches the full remote ref (e.g. "origin/main").
    public let name: String
    /// Remote prefix stripped ("origin/main" → "main"); equals `name` for locals.
    public let displayName: String
    public let isRemote: Bool
    public let commitDate: Date?
    public let isHead: Bool

    public init(
        name: String,
        displayName: String? = nil,
        isRemote: Bool = false,
        commitDate: Date? = nil,
        isHead: Bool = false
    ) {
        self.name = name
        self.displayName = displayName ?? name
        self.isRemote = isRemote
        self.commitDate = commitDate
        self.isHead = isHead
    }
}

/// Monotonic token gate for async fetches: results carry the token handed out
/// by `begin()`, and only the latest token is accepted. Out-of-order or stale
/// completions (an older fetch finishing after a newer one started, or after
/// `invalidate()`) are dropped.
public struct FetchGeneration: Sendable {
    private var current = 0

    public init() {}

    public mutating func begin() -> Int {
        current += 1
        return current
    }

    public func isCurrent(_ token: Int) -> Bool {
        token == current
    }

    /// Reject every outstanding token without starting a new fetch.
    public mutating func invalidate() {
        current += 1
    }
}

/// Pure state machine of the workspace-creation picker: one query filters
/// branches, PRs, and issues into a sectioned row list with a default
/// selection. Emits semantic rows — presentation and localization stay with
/// the caller.
///
/// Row identity (`Row.id`) is stable across data refreshes: it derives from
/// branch names and item numbers, never list positions, so the caller can
/// preserve the highlighted row when async data lands.
public struct WorkspacePickerModel: Sendable {

    // MARK: - Rows

    public enum Row: Sendable, Equatable {
        case branchesHeader
        case pullRequestsHeader
        case issuesHeader
        /// A pasted PR URL that matches no open PR — not actionable, but
        /// without an explanation the query reads as the panel being broken.
        case unknownPRHint(number: Int)
        /// The typed branch exists but already backs a workspace.
        case branchAlreadyOpenHint(name: String)
        /// Create a new branch with the typed name off the base branch.
        case create(name: String)
        /// Check out an existing branch (a remote one checks out its local name).
        case branch(PickerBranch)
        /// Check out an open PR's head branch.
        case pr(GitHubWorkItem)
        /// Create the derived `issue-<n>-<slug>` branch off the base branch.
        case issue(GitHubWorkItem)

        public var id: String {
            switch self {
            case .branchesHeader: return "header-branches"
            case .pullRequestsHeader: return "header-prs"
            case .issuesHeader: return "header-issues"
            case .unknownPRHint(let number): return "hint-unknown-pr-\(number)"
            case .branchAlreadyOpenHint(let name): return "hint-open-\(name)"
            case .create: return "create"
            case .branch(let branch): return "branch-\(branch.name)"
            case .pr(let item): return "pr-\(item.number)"
            case .issue(let item): return "issue-\(item.number)"
            }
        }

        public var isSelectable: Bool {
            switch self {
            case .branchesHeader, .pullRequestsHeader, .issuesHeader,
                 .unknownPRHint, .branchAlreadyOpenHint:
                return false
            case .create, .branch, .pr, .issue:
                return true
            }
        }

        /// Whether confirming this row creates a new branch — the Base branch
        /// accessory is only meaningful then.
        public var createsNewBranch: Bool {
            switch self {
            case .create, .issue: return true
            default: return false
            }
        }
    }

    // MARK: - Inputs

    public let branches: [PickerBranch]
    public let githubItems: [GitHubWorkItem]
    /// Branches already backing a workspace — excluded from the checkout list
    /// (and PRs whose head is such a branch).
    public let excludedBranches: Set<String>

    private static let fallbackBranch = "main"

    public init(
        branches: [PickerBranch] = [],
        githubItems: [GitHubWorkItem] = [],
        excludedBranches: Set<String> = []
    ) {
        self.branches = branches
        self.githubItems = githubItems
        self.excludedBranches = excludedBranches
    }

    // MARK: - Base branch

    public var localBranchNames: [String] {
        branches.filter { !$0.isRemote }.map(\.name)
    }

    /// "main", "master", the HEAD branch, or the first local branch.
    public var defaultBaseBranch: String {
        let locals = branches.filter { !$0.isRemote }
        if let main = locals.first(where: { $0.name == "main" }) { return main.name }
        if let master = locals.first(where: { $0.name == "master" }) { return master.name }
        if let head = locals.first(where: { $0.isHead }) { return head.name }
        return locals.first?.name ?? Self.fallbackBranch
    }

    // MARK: - Query normalization

    /// A pasted GitHub URL becomes a searchable reference: a known item turns
    /// into its `#n` query, an unknown issue still works as a derived branch
    /// name. An unknown PR cannot be checked out (no head ref), so the URL is
    /// left in place and `rows(for:)` explains it. Returns nil when the text
    /// needs no rewrite.
    public func normalizedQuery(for text: String) -> String? {
        guard let (kind, number) = GitHubWorkItem.parseURL(text) else { return nil }
        if githubItems.contains(where: { $0.kind == kind && $0.number == number }) {
            return "#\(number)"
        }
        if kind == .issue {
            return GitHubWorkItem.issueBranchName(number: number, title: "")
        }
        return nil
    }

    // MARK: - Rows

    /// Create → Branches → Pull Requests → Issues, all filtered by one query.
    public func rows(for query: String) -> [Row] {
        let query = query.trimmingCharacters(in: .whitespaces)
        let q = query.lowercased()
        let referencedNumber = hashNumber(in: query)
        let exact = exactMatch(for: query)
        var rows: [Row] = []

        if let (kind, number) = GitHubWorkItem.parseURL(query) {
            // Only an unknown PR URL survives normalization un-rewritten; a URL
            // is never a valid branch name, so explain instead of offering a
            // doomed create row.
            if kind == .pullRequest {
                rows.append(.unknownPRHint(number: number))
            }
        } else if !query.isEmpty, referencedNumber == nil, exact == nil {
            rows.append(.create(name: query))
        } else if let exact, !exact.isRemote, excludedBranches.contains(exact.name) {
            rows.append(.branchAlreadyOpenHint(name: exact.name))
        }

        var checkout = checkoutBranches(matching: query)
        // An exact match on a remote-only branch stays selectable even though
        // the list is local: typing its full name checks it out.
        if let exact, exact.isRemote, !checkout.contains(where: { $0.name == exact.name }) {
            checkout.insert(exact, at: 0)
        }
        if !checkout.isEmpty {
            rows.append(.branchesHeader)
            rows.append(contentsOf: checkout.map { .branch($0) })
        }

        func matches(_ item: GitHubWorkItem) -> Bool {
            if let referencedNumber { return item.number == referencedNumber }
            guard !q.isEmpty else { return true }
            let haystack = "#\(item.number) \(item.title) \(item.headRefName ?? "")".lowercased()
            return haystack.contains(q)
        }

        let prs = githubItems.filter { item in
            guard item.kind == .pullRequest else { return false }
            if let head = item.headRefName, !head.isEmpty, excludedBranches.contains(head) { return false }
            return matches(item)
        }
        if !prs.isEmpty {
            rows.append(.pullRequestsHeader)
            rows.append(contentsOf: prs.map { .pr($0) })
        }

        let issues = githubItems.filter { $0.kind == .issue && matches($0) }
        if !issues.isEmpty {
            rows.append(.issuesHeader)
            rows.append(contentsOf: issues.map { .issue($0) })
        }
        return rows
    }

    /// The row Enter should act on without arrowing: the create row when the
    /// typed name is new, the matching branch row when it already exists, the
    /// referenced item for a `#123` query. An empty query selects nothing so
    /// Enter can't fire on an arbitrary first row.
    public func defaultSelectionId(for query: String, in rows: [Row]) -> String? {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return nil }

        if case .create? = rows.first { return rows[0].id }

        if let referencedNumber = hashNumber(in: query),
           let row = rows.first(where: {
               switch $0 {
               case .pr(let item), .issue(let item): return item.number == referencedNumber
               default: return false
               }
           }) {
            return row.id
        }

        if let exact = exactMatch(for: query),
           let row = rows.first(where: {
               if case .branch(let branch) = $0 { return branch.name == exact.name }
               return false
           }) {
            return row.id
        }
        return nil
    }

    // MARK: - Branch filtering

    /// Local branches available to check out: excludes any branch that already
    /// backs a workspace, then narrows by a case-insensitive substring query.
    func checkoutBranches(matching query: String) -> [PickerBranch] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return branches.filter { branch in
            guard !branch.isRemote, !excludedBranches.contains(branch.name) else { return false }
            guard !q.isEmpty else { return true }
            return branch.name.lowercased().contains(q)
        }
    }

    /// The branch whose checkout name exactly matches the query, if any.
    func exactMatch(for query: String) -> PickerBranch? {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }
        return branches.first { branch in
            let name = branch.isRemote ? branch.displayName : branch.name
            return name.lowercased() == trimmed
        }
    }

    /// A bare `#123` reference (trimmed, digits only).
    func hashNumber(in text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        let digits = trimmed.dropFirst()
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }
        return Int(digits)
    }
}
