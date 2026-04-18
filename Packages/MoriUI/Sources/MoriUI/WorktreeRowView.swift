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
    let onSelect: () -> Void
    var onRemove: (() -> Void)?

    @State private var isHovered = false

    public init(
        worktree: Worktree,
        agentName: String? = nil,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        onRemove: (() -> Void)? = nil
    ) {
        self.worktree = worktree
        self.agentName = agentName
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onRemove = onRemove
    }

    public var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: MoriTokens.Spacing.lg) {
                iconView

                VStack(alignment: .leading, spacing: MoriTokens.Spacing.xxs) {
                    HStack(spacing: MoriTokens.Spacing.sm) {
                        Text(worktree.name)
                            .font(MoriTokens.Font.rowTitle)
                            .lineLimit(1)

                        if isSelected {
                            selectedAgentLabel
                        }
                    }

                    subtitleLine
                }

                Spacer(minLength: 0)

                primaryBadge

                if isHovered {
                    overflowMenu
                        .transition(.opacity)
                }
            }
            .padding(.vertical, 9)
            .padding(.horizontal, MoriTokens.Spacing.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if isSelected {
                // 2pt accent bar, inset 6pt top/bottom, rounded on the trailing edge.
                // Mirrors `.wt.sel::before` in the V1 design.
                Rectangle()
                    .fill(MoriTokens.Color.active)
                    .frame(width: 2)
                    .padding(.vertical, 6)
                    .clipShape(RoundedRectangle(cornerRadius: 1))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: MoriTokens.Radius.small))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
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
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? MoriTokens.Color.active : MoriTokens.Color.muted)
        }
    }

    private var selectedAgentLabel: some View {
        Group {
            if let agentName, worktree.agentState != .none {
                Text(agentName)
                    .font(MoriTokens.Font.caption)
                    .foregroundStyle(MoriTokens.Color.muted)
                    .lineLimit(1)
            }
        }
    }

    private var subtitleLine: some View {
        HStack(spacing: MoriTokens.Spacing.sm) {
            if let branchText = branchText {
                Text(branchText)
                    .font(MoriTokens.Font.monoBranch)
                    .foregroundStyle(MoriTokens.Color.muted)
                    .lineLimit(1)
            }

            if worktree.status == .active {
                Circle()
                    .fill(MoriTokens.Color.success)
                    .frame(width: MoriTokens.Icon.dot, height: MoriTokens.Icon.dot)
                    .accessibilityLabel(String.localized("Active"))
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
                .font(MoriTokens.Font.caption)
                .foregroundStyle(style.color)
                .padding(.horizontal, MoriTokens.Spacing.sm)
                .padding(.vertical, MoriTokens.Spacing.xxs)
                .background(style.color.opacity(MoriTokens.Opacity.subtle))
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
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MoriTokens.Color.muted)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 16)
        .help(String.localized("More Actions"))
    }

    private var rowBackground: AnyShapeStyle {
        if isSelected {
            // Left-anchored gradient fade — accent fog on the left, clear on the right.
            // Gives the selected row real presence without a flat tinted block.
            let gradient = LinearGradient(
                gradient: Gradient(colors: [
                    MoriTokens.Color.active.opacity(MoriTokens.Opacity.light),
                    Color.clear
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
            return AnyShapeStyle(gradient)
        }
        if isHovered {
            return AnyShapeStyle(MoriTokens.Color.muted.opacity(MoriTokens.Opacity.subtle))
        }
        return AnyShapeStyle(Color.clear)
    }

    // MARK: - Derived Content

    private var worktreeIcon: String {
        if worktree.branch == nil {
            return "house.fill"
        }
        return worktree.isMainWorktree ? "star.fill" : "arrow.triangle.branch"
    }

    private var branchText: String? {
        guard let branch = worktree.branch, branch != worktree.name else { return nil }
        return branch
    }

    private var relativeTimeText: String? {
        guard let date = worktree.lastActiveAt else { return nil }
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return String.localized("just now") }
        if seconds < 3600 { return String.localized("\(seconds / 60)m ago") }
        if seconds < 86400 { return String.localized("\(seconds / 3600)h ago") }
        if seconds < 604_800 { return String.localized("\(seconds / 86400)d ago") }
        return nil
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
