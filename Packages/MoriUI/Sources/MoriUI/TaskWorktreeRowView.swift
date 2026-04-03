import SwiftUI
import MoriCore

/// A row representing a worktree in task mode: worktree name + project name + git status + alert badge.
public struct TaskWorktreeRowView: View {
    let worktree: Worktree
    let projectName: String
    let agentName: String?
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    public init(
        worktree: Worktree,
        projectName: String,
        agentName: String? = nil,
        isSelected: Bool,
        onSelect: @escaping () -> Void
    ) {
        self.worktree = worktree
        self.projectName = projectName
        self.agentName = agentName
        self.isSelected = isSelected
        self.onSelect = onSelect
    }

    public var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: MoriTokens.Spacing.md) {
                Image(systemName: worktreeIcon)
                    .font(MoriTokens.Font.label)
                    .foregroundStyle(worktree.isMainWorktree ? MoriTokens.Color.attention : MoriTokens.Color.muted)

                VStack(alignment: .leading, spacing: MoriTokens.Spacing.xxs) {
                    HStack(spacing: MoriTokens.Spacing.sm) {
                        Text(worktree.name)
                            .font(.system(.body, weight: .semibold))
                            .lineLimit(1)

                        gitStatusBadges
                    }

                    HStack(spacing: MoriTokens.Spacing.sm) {
                        Text(projectName)
                            .font(MoriTokens.Font.caption)
                            .foregroundStyle(MoriTokens.Color.muted)
                            .lineLimit(1)

                        if worktree.status == .active {
                            Circle()
                                .fill(MoriTokens.Color.success)
                                .frame(width: MoriTokens.Icon.dot, height: MoriTokens.Icon.dot)
                                .accessibilityLabel("Active")
                        }

                        if let timeText = relativeTimeText {
                            Text(timeText)
                                .font(MoriTokens.Font.caption)
                                .foregroundStyle(MoriTokens.Color.inactive)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 0)

                alertBadgeView
            }
            .padding(.vertical, MoriTokens.Spacing.md)
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

    // MARK: - Icon

    private var worktreeIcon: String {
        if worktree.branch == nil {
            return "house.fill"
        }
        return worktree.isMainWorktree ? "star.fill" : "arrow.triangle.branch"
    }

    // MARK: - Row Background

    private var rowBackground: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(MoriTokens.Color.active.opacity(MoriTokens.Opacity.light))
        } else if isHovered {
            return AnyShapeStyle(MoriTokens.Color.muted.opacity(MoriTokens.Opacity.subtle))
        } else {
            return AnyShapeStyle(Color.clear)
        }
    }

    // MARK: - Relative Time

    private var relativeTimeText: String? {
        guard let date = worktree.lastActiveAt else { return nil }
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return String.localized("just now") }
        if seconds < 3600 { return String.localized("\(seconds / 60)m ago") }
        if seconds < 86400 { return String.localized("\(seconds / 3600)h ago") }
        if seconds < 604_800 { return String.localized("\(seconds / 86400)d ago") }
        return nil
    }

    // MARK: - Git Status Badges

    @ViewBuilder
    private var gitStatusBadges: some View {
        let indicators = gitStatusIndicators
        if !indicators.isEmpty {
            HStack(spacing: MoriTokens.Spacing.sm) {
                ForEach(indicators, id: \.label) { indicator in
                    Text(indicator.text)
                        .font(MoriTokens.Font.monoSmall)
                        .foregroundStyle(indicator.color)
                        .accessibilityLabel(indicator.label)
                }
            }
            .padding(.horizontal, MoriTokens.Spacing.sm)
            .padding(.vertical, MoriTokens.Spacing.xxs)
            .background(MoriTokens.Color.muted.opacity(MoriTokens.Opacity.subtle))
            .clipShape(RoundedRectangle(cornerRadius: MoriTokens.Radius.small))
        }
    }

    private var gitStatusIndicators: [(text: String, color: Color, label: String)] {
        var result: [(text: String, color: Color, label: String)] = []
        if !worktree.hasUpstream && worktree.branch != nil {
            result.append(("⊘", MoriTokens.Color.info, "No upstream"))
        }
        if worktree.aheadCount > 0 {
            result.append(("↑\(worktree.aheadCount)", MoriTokens.Color.success, "\(worktree.aheadCount) ahead"))
        }
        if worktree.behindCount > 0 {
            result.append(("↓\(worktree.behindCount)", MoriTokens.Color.error, "\(worktree.behindCount) behind"))
        }
        if worktree.stagedCount > 0 {
            result.append(("+\(worktree.stagedCount)", MoriTokens.Color.success, "\(worktree.stagedCount) staged"))
        }
        if worktree.modifiedCount > 0 {
            result.append(("~\(worktree.modifiedCount)", MoriTokens.Color.warning, "\(worktree.modifiedCount) modified"))
        }
        if worktree.untrackedCount > 0 {
            result.append(("?\(worktree.untrackedCount)", MoriTokens.Color.inactive, "\(worktree.untrackedCount) untracked"))
        }
        return result
    }

    /// Combined agent state derived from the worktree's own state and its windows.
    private var effectiveAgentLabel: (icon: String, color: Color, help: String, name: String?)? {
        // Use worktree-level agentState which reflects the most relevant window
        switch worktree.agentState {
        case .error:
            return ("xmark.circle.fill", MoriTokens.Color.error, "Agent error", agentName)
        case .waitingForInput:
            return ("exclamationmark.bubble.fill", MoriTokens.Color.attention, "Agent waiting for input", agentName)
        case .running:
            return ("bolt.fill", MoriTokens.Color.success, "Agent running", agentName)
        case .completed:
            return ("checkmark.circle.fill", MoriTokens.Color.success, "Agent completed", agentName)
        case .none:
            return nil
        }
    }

    // MARK: - Alert Badge

    @ViewBuilder
    private var alertBadgeView: some View {
        if let label = effectiveAgentLabel {
            HStack(spacing: MoriTokens.Spacing.xxs) {
                Image(systemName: label.icon)
                    .font(.system(size: MoriTokens.Icon.badge))
                    .foregroundStyle(label.color)
                if let name = label.name {
                    Text(name)
                        .font(MoriTokens.Font.monoSmall)
                        .foregroundStyle(label.color)
                        .lineLimit(1)
                }
            }
            .help(label.help)
            .accessibilityLabel(label.help)
        }
    }
}
