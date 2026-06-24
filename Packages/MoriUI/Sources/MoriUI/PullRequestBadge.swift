import SwiftUI
import MoriCore

/// Compact inline PR indicator shown on the worktree row itself (not a sub-row),
/// so the sidebar stays two levels. Reads at a glance — `#number` tinted by PR
/// state, plus a CI check glyph; the exact state spells out in the tooltip.
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

    /// Short state used in the tooltip — review decision wins over a plain "open".
    private var stateLabel: String {
        if info.isDraft { return "Draft" }
        switch info.state {
        case .merged: return "Merged"
        case .closed: return "Closed"
        case .open:
            switch info.reviewDecision {
            case .changesRequested: return "Changes requested"
            case .approved: return "Approved"
            case .required: return "Review required"
            case .none: return "Open"
            }
        }
    }

    private var stateColor: Color {
        if info.isDraft { return MoriTokens.Color.muted }
        switch info.state {
        case .merged: return MoriTokens.Color.active
        case .closed: return MoriTokens.Color.error
        case .open:
            switch info.reviewDecision {
            case .changesRequested: return MoriTokens.Color.error
            case .approved: return MoriTokens.Color.success
            case .required: return MoriTokens.Color.info
            case .none: return MoriTokens.Color.success
            }
        }
    }
}
