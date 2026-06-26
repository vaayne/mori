import SwiftUI
import MoriCore

/// Compact PR indicator for the worktree metadata line. Keeping it off the
/// primary row lets the full PR number show without competing with the worktree name.
///
/// Deliberately non-interactive: opening the PR in a browser is heavyweight and
/// hard to undo, so it lives in the row's right-click menu rather than as a click
/// target inside the selection row, where a stray click would fire it.
struct PullRequestBadge: View {
    let info: PullRequestInfo
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 3) {
            Text("#\(info.number)")
                .font(MoriTokens.Font.monoSmall)
                .foregroundStyle(numberColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            checksGlyph
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(
            Capsule().fill(isSelected
                ? Color.white.opacity(0.18)
                : stateColor.opacity(0.14))
        )
        .help("\(stateLabel) · #\(info.number) — right-click the worktree to open\n\(info.url)")
    }

    private var numberColor: Color {
        isSelected ? Color.white.opacity(0.9) : stateColor
    }

    @ViewBuilder
    private var checksGlyph: some View {
        switch info.checks {
        case .passing: glyph("checkmark", MoriTokens.Color.success)
        case .failing: glyph("xmark", MoriTokens.Color.error)
        case .pending: glyph("clock", MoriTokens.Color.warning)
        case .none: EmptyView()
        }
    }

    private func glyph(_ name: String, _ color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(isSelected ? Color.white.opacity(0.85) : color)
    }

    /// The PR's display state, derived once (draft wins, then merged/closed, then
    /// the review decision on an open PR) so the label and color can't diverge.
    private enum DisplayState {
        case draft, merged, closed, open, reviewRequired, approved, changesRequested
    }

    private var displayState: DisplayState {
        if info.isDraft { return .draft }
        switch info.state {
        case .merged: return .merged
        case .closed: return .closed
        case .open:
            switch info.reviewDecision {
            case .changesRequested: return .changesRequested
            case .approved: return .approved
            case .required: return .reviewRequired
            case .none: return .open
            }
        }
    }

    /// Short state used in the tooltip.
    private var stateLabel: String {
        switch displayState {
        case .draft: return "Draft"
        case .merged: return "Merged"
        case .closed: return "Closed"
        case .open: return "Open"
        case .reviewRequired: return "Review required"
        case .approved: return "Approved"
        case .changesRequested: return "Changes requested"
        }
    }

    private var stateColor: Color {
        switch displayState {
        case .draft: return MoriTokens.Color.muted
        case .merged: return MoriTokens.Color.active
        case .closed, .changesRequested: return MoriTokens.Color.error
        case .open, .approved: return MoriTokens.Color.success
        case .reviewRequired: return MoriTokens.Color.info
        }
    }
}
