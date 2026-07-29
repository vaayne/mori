import Foundation

/// A snapshot of the GitHub pull request associated with a worktree's branch.
///
/// Populated live from `gh pr view <branch> --json …`; never persisted (it is
/// volatile and re-fetched on demand). Absence of an entry for a worktree means
/// "no PR, or not fetched yet" — both render as nothing in the UI.
public struct PullRequestInfo: Equatable, Sendable {
    public enum State: String, Sendable {
        case open, closed, merged
    }

    /// Aggregate CI status rolled up from all check runs / status contexts.
    public enum Checks: Sendable {
        case none      // no checks configured
        case pending   // at least one still running, none failing
        case passing   // all completed successfully
        case failing   // at least one failed
    }

    public enum ReviewDecision: Sendable {
        case none      // no review required / requested
        case required  // review required, not yet given
        case approved
        case changesRequested
    }

    public let number: Int
    public let title: String
    public let url: String
    public let state: State
    public let isDraft: Bool
    public let checks: Checks
    public let reviewDecision: ReviewDecision

    public init(
        number: Int,
        title: String,
        url: String,
        state: State,
        isDraft: Bool,
        checks: Checks,
        reviewDecision: ReviewDecision
    ) {
        self.number = number
        self.title = title
        self.url = url
        self.state = state
        self.isDraft = isDraft
        self.checks = checks
        self.reviewDecision = reviewDecision
    }

    /// Parse the JSON object emitted by
    /// `gh pr view <branch> --json number,title,url,state,isDraft,reviewDecision,statusCheckRollup`.
    /// Returns nil when the payload can't be decoded.
    public static func parse(jsonData: Data) -> PullRequestInfo? {
        guard let dto = try? JSONDecoder().decode(GhPullRequestDTO.self, from: jsonData) else {
            return nil
        }
        return dto.info
    }

    /// Parse the JSON array emitted by `gh pr list --json <fields>,headRefName`
    /// into a head-branch → PR map, so one repo-wide query can update every
    /// worktree's badge. Returns nil when the payload can't be decoded (callers
    /// treat that as "fetch failed", distinct from "no open PRs" → empty map).
    ///
    /// Entries without a headRefName are skipped. On duplicate head branches
    /// (e.g. same-named branches in two forks) the first entry wins — gh lists
    /// newest first.
    public static func parseListByBranch(jsonData: Data) -> [String: PullRequestInfo]? {
        guard let dtos = try? JSONDecoder().decode([GhPullRequestDTO].self, from: jsonData) else {
            return nil
        }
        var byBranch: [String: PullRequestInfo] = [:]
        for dto in dtos {
            guard let head = dto.headRefName, !head.isEmpty, byBranch[head] == nil else { continue }
            byBranch[head] = dto.info
        }
        return byBranch
    }

    /// Collapse the heterogeneous check list (CheckRun + StatusContext) into one
    /// status. Any failure wins, then any pending, then passing, else none.
    fileprivate static func rollUpChecks(_ items: [GhCheckDTO]) -> Checks {
        guard !items.isEmpty else { return .none }
        var sawPending = false
        for item in items {
            switch item.result {
            case .failing: return .failing
            case .pending: sawPending = true
            case .passing: break
            }
        }
        return sawPending ? .pending : .passing
    }
}

// MARK: - gh JSON DTOs

private struct GhPullRequestDTO: Decodable {
    let number: Int
    let title: String
    let url: String
    let state: String
    let isDraft: Bool?
    let reviewDecision: String?
    let statusCheckRollup: [GhCheckDTO]?
    /// Present only in `gh pr list` payloads that request it.
    let headRefName: String?

    var info: PullRequestInfo {
        let state: PullRequestInfo.State = switch state.uppercased() {
        case "MERGED": .merged
        case "CLOSED": .closed
        default: .open
        }
        let review: PullRequestInfo.ReviewDecision = switch (reviewDecision ?? "").uppercased() {
        case "APPROVED": .approved
        case "CHANGES_REQUESTED": .changesRequested
        case "REVIEW_REQUIRED": .required
        default: .none
        }
        return PullRequestInfo(
            number: number,
            title: title,
            url: url,
            state: state,
            isDraft: isDraft ?? false,
            checks: PullRequestInfo.rollUpChecks(statusCheckRollup ?? []),
            reviewDecision: review
        )
    }
}

/// A single entry in `statusCheckRollup`. GitHub mixes two shapes: GitHub Actions
/// `CheckRun` (status + conclusion) and external `StatusContext` (state). Decode
/// all three optionally and normalize.
private struct GhCheckDTO: Decodable {
    enum Result { case passing, pending, failing }

    let status: String?       // CheckRun: QUEUED | IN_PROGRESS | COMPLETED
    let conclusion: String?   // CheckRun: SUCCESS | FAILURE | NEUTRAL | …
    let state: String?        // StatusContext: SUCCESS | FAILURE | PENDING | ERROR

    var result: Result {
        if let conclusion, !conclusion.isEmpty {
            switch conclusion.uppercased() {
            case "SUCCESS", "NEUTRAL", "SKIPPED": return .passing
            case "FAILURE", "CANCELLED", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE", "STALE":
                return .failing
            default: return .pending
            }
        }
        if let state, !state.isEmpty {
            switch state.uppercased() {
            case "SUCCESS": return .passing
            case "FAILURE", "ERROR": return .failing
            default: return .pending
            }
        }
        // CheckRun not yet completed (no conclusion).
        return (status?.uppercased() == "COMPLETED") ? .passing : .pending
    }
}
