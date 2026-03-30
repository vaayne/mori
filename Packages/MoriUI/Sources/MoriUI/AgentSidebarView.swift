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

    @State private var collapsedGroups: Set<AgentGroupKey> = []

    public init(
        projects: [Project] = [],
        worktrees: [Worktree],
        windows: [RuntimeWindow],
        selectedWindowId: String?,
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
        self.onSelectWindow = onSelectWindow
        self.onRequestPaneOutput = onRequestPaneOutput
        self.onSendKeys = onSendKeys
        self.onAddProject = onAddProject
        self.onOpenSettings = onOpenSettings
        self.onOpenCommandPalette = onOpenCommandPalette
    }

    /// Agent windows: those with a detected agent or non-none agentState.
    private var agentWindows: [RuntimeWindow] {
        windows.filter { $0.detectedAgent != nil || $0.agentState != .none }
    }

    private var projectMap: [UUID: Project] {
        Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
    }

    private var worktreeMap: [UUID: Worktree] {
        Dictionary(uniqueKeysWithValues: worktrees.map { ($0.id, $0) })
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

                Text(group.title)
                    .font(MoriTokens.Font.sectionTitle)
                    .foregroundStyle(MoriTokens.Color.muted)

                Text("\(windows.count)")
                    .font(MoriTokens.Font.badgeCount)
                    .foregroundStyle(MoriTokens.Color.muted)

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
            Image(systemName: "person.2.slash")
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
                    .help("Add Repository")
                    .accessibilityLabel("Add Repository")
                }

                Spacer()

                if let onOpenCommandPalette {
                    Button(action: onOpenCommandPalette) {
                        Image(systemName: "text.magnifyingglass")
                            .font(.system(size: 13))
                            .foregroundStyle(MoriTokens.Color.muted)
                    }
                    .buttonStyle(.plain)
                    .help("Command Palette (⇧⌘P)")
                    .accessibilityLabel("Command Palette")
                }

                if let onOpenSettings {
                    Button(action: onOpenSettings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13))
                            .foregroundStyle(MoriTokens.Color.muted)
                    }
                    .buttonStyle(.plain)
                    .help("Settings (⌘,)")
                    .accessibilityLabel("Settings")
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
    case idle

    /// Display order: attention first, then running, completed, idle.
    static let displayOrder: [AgentGroupKey] = [.attention, .running, .completed, .idle]

    var title: String {
        switch self {
        case .attention: return String.localized("Attention")
        case .running: return String.localized("Running")
        case .completed: return String.localized("Completed")
        case .idle: return String.localized("Idle")
        }
    }

    func matches(_ window: RuntimeWindow) -> Bool {
        switch self {
        case .attention:
            return window.agentState == .waitingForInput || window.agentState == .error
        case .running:
            return window.agentState == .running
        case .completed:
            return window.agentState == .completed
        case .idle:
            return window.agentState == .none
        }
    }
}
