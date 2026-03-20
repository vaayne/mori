import SwiftUI
import MoriCore

/// A two-line row representing a single worktree: bold name + subtitle with status.
/// Shows a hover-reveal `...` menu for management actions.
public struct WorktreeRowView: View {
    let worktree: Worktree
    let isSelected: Bool
    let onSelect: () -> Void
    var onRemove: (() -> Void)?

    @State private var isHovered = false

    public init(
        worktree: Worktree,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        onRemove: (() -> Void)? = nil
    ) {
        self.worktree = worktree
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onRemove = onRemove
    }

    public var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: MoriTokens.Spacing.md) {
                Image(systemName: worktree.isMainWorktree ? "star.fill" : "arrow.triangle.branch")
                    .font(MoriTokens.Font.label)
                    .foregroundStyle(worktree.isMainWorktree ? MoriTokens.Color.attention : MoriTokens.Color.muted)

                VStack(alignment: .leading, spacing: MoriTokens.Spacing.xxs) {
                    HStack(spacing: MoriTokens.Spacing.sm) {
                        Text(worktree.branch ?? worktree.name)
                            .font(.system(.body, weight: .semibold))
                            .lineLimit(1)

                        gitStatusBadges
                    }

                    subtitleText
                }

                Spacer(minLength: 0)

                alertBadgeView

                if isHovered {
                    overflowMenu
                        .transition(.opacity)
                }
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
        .help("More Actions")
    }

    private var rowBackground: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(MoriTokens.Color.active.opacity(MoriTokens.Opacity.light))
        } else if isHovered {
            return AnyShapeStyle(MoriTokens.Color.muted.opacity(MoriTokens.Opacity.subtle))
        } else {
            return AnyShapeStyle(Color.clear)
        }
    }

    // MARK: - Subtitle

    private var subtitleText: some View {
        HStack(spacing: MoriTokens.Spacing.sm) {
            Text(worktree.name)
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

    private var relativeTimeText: String? {
        guard let date = worktree.lastActiveAt else { return nil }
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        if seconds < 604_800 { return "\(seconds / 86400)d ago" }
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

    // MARK: - Alert Badge

    @ViewBuilder
    private var alertBadgeView: some View {
        switch worktree.agentState {
        case .error:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: MoriTokens.Icon.badge))
                .foregroundStyle(MoriTokens.Color.error)
                .help("Agent error")
                .accessibilityLabel("Agent error")
        case .waitingForInput:
            Image(systemName: "exclamationmark.bubble.fill")
                .font(.system(size: MoriTokens.Icon.badge))
                .foregroundStyle(MoriTokens.Color.attention)
                .help("Agent waiting for input")
                .accessibilityLabel("Agent waiting for input")
        case .running:
            Image(systemName: "bolt.fill")
                .font(.system(size: MoriTokens.Icon.badge))
                .foregroundStyle(MoriTokens.Color.success)
                .help("Agent running")
                .accessibilityLabel("Agent running")
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: MoriTokens.Icon.badge))
                .foregroundStyle(MoriTokens.Color.success)
                .help("Agent completed")
                .accessibilityLabel("Agent completed")
        case .none:
            EmptyView()
        }
    }
}
