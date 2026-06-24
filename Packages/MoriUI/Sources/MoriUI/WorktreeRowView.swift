import SwiftUI
import MoriCore

/// A compact worktree row with a single primary status badge.
/// Secondary metadata stays on the subtitle line to keep scanning easy.
public struct WorktreeRowView: View {
    private struct PrimaryBadgeStyle {
        let title: String
        let color: Color
        let accessibilityLabel: String
    }

    let worktree: Worktree
    let agentName: String?
    let isSelected: Bool
    /// Number of tmux windows in this worktree. A chip appears when > 1 so the
    /// second level stays collapsed by default (keeps the tree at two levels).
    let windowCount: Int
    let isExpanded: Bool
    /// Non-nil when a *hidden* window needs attention while collapsed; drives a
    /// small dot on the chip so alerts surface without forcing the level open.
    let hiddenAlertColor: Color?
    /// GitHub PR for this worktree's branch. Rendered as a status strip below the
    /// row only while selected, keeping the sidebar quiet for unselected rows.
    let pullRequest: PullRequestInfo?
    let onSelect: () -> Void
    var onToggleExpand: (() -> Void)?
    var onRemove: (() -> Void)?

    @State private var isHovered = false

    public init(
        worktree: Worktree,
        agentName: String? = nil,
        isSelected: Bool,
        windowCount: Int = 0,
        isExpanded: Bool = false,
        hiddenAlertColor: Color? = nil,
        pullRequest: PullRequestInfo? = nil,
        onSelect: @escaping () -> Void,
        onToggleExpand: (() -> Void)? = nil,
        onRemove: (() -> Void)? = nil
    ) {
        self.worktree = worktree
        self.agentName = agentName
        self.isSelected = isSelected
        self.windowCount = windowCount
        self.isExpanded = isExpanded
        self.hiddenAlertColor = hiddenAlertColor
        self.pullRequest = pullRequest
        self.onSelect = onSelect
        self.onToggleExpand = onToggleExpand
        self.onRemove = onRemove
    }

    public var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: MoriTokens.Spacing.md) {
                // Leading glyph fuses identity (branch vs session) and agent state
                // into one 17pt symbol — pulses while an agent waits on you.
                Image(systemName: worktreeIcon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(glyphColor)
                    .frame(width: 17, height: 17)
                    .symbolEffect(.pulse, options: .repeating, isActive: worktree.agentState == .waitingForInput)

                Text(branchDisplayText)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(nameColor)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let gitSummaryText {
                    Text(gitSummaryText)
                        .font(MoriTokens.Font.monoSmall)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.85) : MoriTokens.Color.muted)
                        .lineLimit(1)
                }

                if let pullRequest {
                    PullRequestBadge(info: pullRequest, isSelected: isSelected)
                }

                windowChip

                if isHovered {
                    overflowMenu
                        .transition(.opacity)
                } else if let timeText = relativeTimeText {
                    Text(timeText)
                        .font(MoriTokens.Font.monoShortcut)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.7) : MoriTokens.Color.inactive)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, MoriTokens.Spacing.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: MoriTokens.Radius.small))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    /// Tint for the leading glyph: agent state first, then live/idle session.
    private var glyphColor: Color {
        if isSelected { return .white }
        switch worktree.agentState {
        case .error: return MoriTokens.Color.error
        case .waitingForInput: return MoriTokens.Color.attention
        case .running, .completed: return MoriTokens.Color.success
        case .none:
            return worktree.status == .active ? Color.primary.opacity(0.75) : MoriTokens.Color.inactive
        }
    }

    private var nameColor: Color {
        if isSelected { return .white }
        return (worktree.status == .active || worktree.agentState != .none)
            ? Color.primary : MoriTokens.Color.muted
    }

    /// Collapsed-by-default window count. Tapping toggles the third level so it
    /// only appears on demand; a dot warns when a hidden window needs attention.
    @ViewBuilder
    private var windowChip: some View {
        if windowCount >= 2, let onToggleExpand {
            Button(action: onToggleExpand) {
                HStack(spacing: 2) {
                    Text("\(windowCount)")
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .font(MoriTokens.Font.monoShortcut)
                .foregroundStyle(isSelected ? Color.white.opacity(0.85) : MoriTokens.Color.muted)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(isSelected
                        ? Color.white.opacity(0.18)
                        : MoriTokens.Color.muted.opacity(MoriTokens.Opacity.light))
                )
                .overlay(alignment: .topTrailing) {
                    if let hiddenAlertColor, !isExpanded {
                        Circle()
                            .fill(hiddenAlertColor)
                            .frame(width: 5, height: 5)
                            .offset(x: 2, y: -2)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var iconView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: MoriTokens.Icon.worktreeBoxRadius)
                .fill(isSelected
                    ? MoriTokens.Color.active.opacity(MoriTokens.Opacity.light)
                    : MoriTokens.Color.muted.opacity(MoriTokens.Opacity.subtle))
                .frame(width: MoriTokens.Icon.worktreeBox, height: MoriTokens.Icon.worktreeBox)
            Image(systemName: worktreeIcon)
                .font(MoriTokens.Font.label)
                .foregroundStyle(isSelected ? MoriTokens.Color.active : MoriTokens.Color.muted)
        }
    }

    private var selectedAgentLabel: some View {
        Group {
            if let agentName, worktree.agentState != .none {
                Text(agentName)
                    .font(MoriTokens.Font.caption)
                    .foregroundStyle(MoriTokens.Color.active.opacity(0.9))
                    .lineLimit(1)
            }
        }
    }

    private var subtitleLine: some View {
        HStack(spacing: MoriTokens.Spacing.sm) {
            if let branchText = branchText {
                Text(branchText)
                    .font(MoriTokens.Font.monoBranch)
                    .foregroundStyle(isSelected ? Color.primary.opacity(0.82) : MoriTokens.Color.muted)
                    .lineLimit(1)
            }

            if let timeText = relativeTimeText {
                Text(timeText)
                    .font(MoriTokens.Font.caption)
                    .foregroundStyle(MoriTokens.Color.inactive)
                    .lineLimit(1)
            }

            if let gitSummaryText {
                Text(gitSummaryText)
                    .font(MoriTokens.Font.monoSmall)
                    .foregroundStyle(MoriTokens.Color.muted)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var primaryBadge: some View {
        if let style = primaryBadgeStyle {
            Text(style.title)
                .font(MoriTokens.Font.badgeText)
                .foregroundStyle(style.color)
                .padding(.horizontal, MoriTokens.Spacing.sm)
                .padding(.vertical, MoriTokens.Spacing.xxs)
                .background(style.color.opacity(isSelected ? MoriTokens.Opacity.light : MoriTokens.Opacity.subtle))
                .clipShape(RoundedRectangle(cornerRadius: MoriTokens.Radius.badge))
                .accessibilityLabel(style.accessibilityLabel)
        }
    }

    // MARK: - Overflow Menu

    private var overflowMenu: some View {
        Menu {
            let editors = EditorLauncher.installed
            if !editors.isEmpty {
                ForEach(editors) { editor in
                    Button {
                        editor.open(path: worktree.path)
                    } label: {
                        Label("Open in \(editor.name)", systemImage: editor.icon)
                    }
                }
                Divider()
            }

            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: worktree.path)
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }

            if !worktree.isMainWorktree, let onRemove {
                Divider()
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label("Remove Worktree…", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(MoriTokens.Font.sidebarAccessory)
                .foregroundStyle(MoriTokens.Color.muted)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: MoriTokens.Size.sidebarAccessory)
        .help(String.localized("More Actions"))
    }

    private var rowBackground: AnyShapeStyle {
        if isSelected {
            // Solid accent fill with white text — unmistakable "you are here".
            return AnyShapeStyle(MoriTokens.Color.active)
        }
        if isHovered {
            return AnyShapeStyle(Color.primary.opacity(MoriTokens.Opacity.subtle))
        }
        return AnyShapeStyle(Color.clear)
    }

    // MARK: - Derived Content

    private var worktreeIcon: String {
        if worktree.isDetached || worktree.branch == nil {
            return "circle.dotted"
        }
        // Main branch reads as a "trunk"; linked worktrees as a node graph,
        // echoing Stella's branch-vs-merge glyph distinction.
        return worktree.isMainWorktree
            ? "arrow.triangle.branch"
            : "point.3.connected.trianglepath.dotted"
    }

    private var branchText: String? {
        guard let branch = worktree.branch, branch != worktree.name else { return nil }
        return branch
    }

    private var relativeTimeText: String? {
        guard let date = worktree.lastActiveAt else { return nil }
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return String.localized("now") }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        if seconds < 604_800 { return "\(seconds / 86400)d" }
        return nil
    }

    private var branchDisplayText: String {
        worktree.branch ?? worktree.name
    }

    private var gitSummaryText: String? {
        var parts: [String] = []

        if worktree.aheadCount > 0 {
            parts.append("↑\(worktree.aheadCount)")
        }
        if worktree.behindCount > 0 {
            parts.append("↓\(worktree.behindCount)")
        }
        if worktree.stagedCount > 0 {
            parts.append("+\(worktree.stagedCount)")
        }
        if worktree.modifiedCount > 0 {
            parts.append("~\(worktree.modifiedCount)")
        }
        if worktree.untrackedCount > 0 {
            parts.append("?\(worktree.untrackedCount)")
        }
        if !worktree.hasUpstream && worktree.branch != nil {
            parts.append("⊘")
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " ")
    }

    private var primaryBadgeStyle: PrimaryBadgeStyle? {
        switch worktree.agentState {
        case .waitingForInput:
            return PrimaryBadgeStyle(
                title: String.localized("Waiting"),
                color: MoriTokens.Color.attention,
                accessibilityLabel: String.localized("Waiting")
            )
        case .error:
            return PrimaryBadgeStyle(
                title: String.localized("Error"),
                color: MoriTokens.Color.error,
                accessibilityLabel: String.localized("Error")
            )
        case .running:
            return PrimaryBadgeStyle(
                title: String.localized("Running"),
                color: MoriTokens.Color.success,
                accessibilityLabel: String.localized("Running")
            )
        case .completed:
            return PrimaryBadgeStyle(
                title: String.localized("Completed"),
                color: MoriTokens.Color.success,
                accessibilityLabel: String.localized("Completed")
            )
        case .none:
            return nil
        }
    }
}
