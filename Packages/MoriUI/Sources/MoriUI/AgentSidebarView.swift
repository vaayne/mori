import SwiftUI
import MoriCore

/// Agent mode sidebar: groups all agent windows across projects by state.
/// Pure SwiftUI view — data + callbacks, no direct AppState dependency.
public struct AgentSidebarView: View {
    private let projects: [Project]
    private let worktrees: [Worktree]
    private let windows: [RuntimeWindow]
    private let selectedWindowId: String?
    private let onSelectWindow: (String) -> Void
    private let onRequestPaneOutput: ((String, @escaping (String?) -> Void) -> Void)?
    private let onSendKeys: ((String, String) -> Void)?
    private let onAddProject: (() -> Void)?
    private let onOpenSettings: (() -> Void)?
    private let onOpenCommandPalette: (() -> Void)?
    private let shortcutHintsVisible: Bool

    @State private var collapsedGroups: Set<AgentGroupKey> = []

    public init(
        projects: [Project] = [],
        worktrees: [Worktree],
        windows: [RuntimeWindow],
        selectedWindowId: String?,
        shortcutHintsVisible: Bool = false,
        onSelectWindow: @escaping (String) -> Void,
        onRequestPaneOutput: ((String, @escaping (String?) -> Void) -> Void)? = nil,
        onSendKeys: ((String, String) -> Void)? = nil,
        onAddProject: (() -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onOpenCommandPalette: (() -> Void)? = nil
    ) {
        self.projects = projects
        self.worktrees = worktrees
        self.windows = windows
        self.selectedWindowId = selectedWindowId
        self.shortcutHintsVisible = shortcutHintsVisible
        self.onSelectWindow = onSelectWindow
        self.onRequestPaneOutput = onRequestPaneOutput
        self.onSendKeys = onSendKeys
        self.onAddProject = onAddProject
        self.onOpenSettings = onOpenSettings
        self.onOpenCommandPalette = onOpenCommandPalette
    }

    /// Agent windows: those with a detected agent or active agent state.
    private var agentWindows: [RuntimeWindow] {
        windows.filter { $0.detectedAgent != nil || $0.agentState != .none }
    }

    private var projectMap: [UUID: Project] {
        Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
    }

    private var worktreeMap: [UUID: Worktree] {
        Dictionary(uniqueKeysWithValues: worktrees.map { ($0.id, $0) })
    }

    /// Global 1-based index for each window across all worktrees.
    private var globalWindowIndices: [String: Int] {
        let availableWorktrees = worktrees.filter { $0.status != .unavailable }
        var result: [String: Int] = [:]
        var globalIndex = 1
        for worktree in availableWorktrees {
            let worktreeWindows = windows
                .filter { $0.worktreeId == worktree.id }
                .sorted { $0.tmuxWindowIndex < $1.tmuxWindowIndex }
            for window in worktreeWindows {
                if globalIndex <= 9 {
                    result[window.tmuxWindowId] = globalIndex
                }
                globalIndex += 1
            }
        }
        return result
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if agentWindows.isEmpty {
                        emptyState
                    } else {
                        ForEach(AgentGroupKey.displayOrder, id: \.self) { group in
                            let groupWindows = windowsForGroup(group)
                            if !groupWindows.isEmpty {
                                groupSection(group: group, windows: groupWindows)
                            }
                        }
                    }
                }
                .padding(.top, MoriTokens.Spacing.lg)
            }

            Spacer(minLength: 0)

            sidebarFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Grouping

    private func windowsForGroup(_ group: AgentGroupKey) -> [RuntimeWindow] {
        agentWindows.filter { group.matches($0) }
    }

    @ViewBuilder
    private func groupSection(group: AgentGroupKey, windows: [RuntimeWindow]) -> some View {
        let isCollapsed = collapsedGroups.contains(group)

        // Header
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isCollapsed {
                    collapsedGroups.remove(group)
                } else {
                    collapsedGroups.insert(group)
                }
            }
        } label: {
            HStack(spacing: MoriTokens.Spacing.md) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MoriTokens.Color.muted)
                    .frame(width: 12)

                Image(systemName: group.iconName)
                    .font(.system(size: 11))
                    .foregroundStyle(group.color)

                Text(group.title)
                    .font(MoriTokens.Font.sectionTitle)
                    .foregroundStyle(group.color)

                Text("\(windows.count)")
                    .font(MoriTokens.Font.badgeCount)
                    .foregroundStyle(group.color.opacity(0.7))

                Spacer()
            }
            .padding(.horizontal, MoriTokens.Spacing.xl)
            .padding(.top, MoriTokens.Spacing.xl)
            .padding(.bottom, MoriTokens.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if !isCollapsed {
            ForEach(windows) { window in
                let worktree = worktreeMap[window.worktreeId]
                let project = worktree.flatMap { projectMap[$0.projectId] }
                AgentWindowRowView(
                    window: window,
                    projectName: project?.name ?? "?",
                    worktreeName: worktree?.name ?? "?",
                    isSelected: window.tmuxWindowId == selectedWindowId,
                    shortcutIndex: globalWindowIndices[window.tmuxWindowId],
                    shortcutHintsVisible: shortcutHintsVisible,
                    onSelect: { onSelectWindow(window.tmuxWindowId) },
                    onRequestPaneOutput: onRequestPaneOutput,
                    onSendKeys: onSendKeys
                )
                .padding(.horizontal, MoriTokens.Spacing.sm)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: MoriTokens.Spacing.lg) {
            Image(systemName: "bolt.slash")
                .font(.system(size: 24))
                .foregroundStyle(MoriTokens.Color.muted)
            Text(String.localized("No agents running"))
                .font(MoriTokens.Font.label)
                .foregroundStyle(MoriTokens.Color.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, MoriTokens.Spacing.emptyState)
    }

    // MARK: - Footer

    private var sidebarFooter: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: MoriTokens.Spacing.xl) {
                if let onAddProject {
                    Button(action: onAddProject) {
                        Image(systemName: "plus.rectangle.on.folder")
                            .font(.system(size: 13))
                            .foregroundStyle(MoriTokens.Color.muted)
                    }
                    .buttonStyle(.plain)
                    .help(String.localized("Add Repository"))
                    .accessibilityLabel(String.localized("Add Repository"))
                }

                Spacer()

                if let onOpenCommandPalette {
                    Button(action: onOpenCommandPalette) {
                        Image(systemName: "text.magnifyingglass")
                            .font(.system(size: 13))
                            .foregroundStyle(MoriTokens.Color.muted)
                    }
                    .buttonStyle(.plain)
                    .help(String.localized("Command Palette (⇧⌘P)"))
                    .accessibilityLabel(String.localized("Command Palette"))
                    .overlay(alignment: .top) {
                        if shortcutHintsVisible {
                            ShortcutHintPill("⇧⌘P")
                                .offset(y: -22)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.14), value: shortcutHintsVisible)
                }

                if let onOpenSettings {
                    Button(action: onOpenSettings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13))
                            .foregroundStyle(MoriTokens.Color.muted)
                    }
                    .buttonStyle(.plain)
                    .help(String.localized("Settings (⌘,)"))
                    .accessibilityLabel(String.localized("Settings"))
                    .overlay(alignment: .top) {
                        if shortcutHintsVisible {
                            ShortcutHintPill("⌘,")
                                .offset(y: -22)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.14), value: shortcutHintsVisible)
                }
            }
            .padding(.horizontal, MoriTokens.Spacing.xl)
            .padding(.vertical, MoriTokens.Spacing.lg)
        }
    }
}

// MARK: - Agent Group Key

enum AgentGroupKey: String, Hashable, CaseIterable {
    case attention
    case running
    case completed

    /// Display order: attention first, then running, completed.
    static let displayOrder: [AgentGroupKey] = [.attention, .running, .completed]

    var title: String {
        switch self {
        case .attention: return String.localized("Attention")
        case .running: return String.localized("Running")
        case .completed: return String.localized("Completed")
        }
    }

    var iconName: String {
        switch self {
        case .attention: return "exclamationmark.bubble.fill"
        case .running: return "bolt.fill"
        case .completed: return "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .attention: return MoriTokens.Color.attention
        case .running: return MoriTokens.Color.success
        case .completed: return MoriTokens.Color.muted
        }
    }

    func matches(_ window: RuntimeWindow) -> Bool {
        switch self {
        case .attention:
            return window.agentState == .waitingForInput || window.agentState == .error
        case .running:
            return window.agentState == .running
        case .completed:
            return window.agentState == .completed || window.agentState == .none
        }
    }
}
