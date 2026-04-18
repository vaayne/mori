import SwiftUI
import MoriCore

/// Unified sidebar: all projects as flat sections, worktrees as two-line rows,
/// windows indented below, and action footer at the bottom.
public struct WorktreeSidebarView: View {
    private let projects: [Project]
    private let selectedProjectId: UUID?
    private let worktrees: [Worktree]
    private let windows: [RuntimeWindow]
    private let selectedWorktreeId: UUID?
    private let selectedWindowId: String?
    private let onSelectProject: ((UUID) -> Void)?
    private let onSelectWorktree: (UUID) -> Void
    private let onSelectWindow: (String) -> Void
    private let onShowCreatePanel: (() -> Void)?
    private let onRemoveWorktree: ((UUID) -> Void)?
    private let onRemoveProject: ((UUID) -> Void)?
    private let onEditRemoteProject: ((UUID) -> Void)?
    private let onCloseWindow: ((String) -> Void)?
    private let onToggleCollapse: ((UUID) -> Void)?
    private let onAddProject: (() -> Void)?
    private let onOpenSettings: (() -> Void)?
    private let onOpenCommandPalette: (() -> Void)?
    private let onRequestPaneOutput: ((String, @escaping (String?) -> Void) -> Void)?
    private let onSendKeys: ((String, String) -> Void)?
    private let onUpdateProject: ((Project) -> Void)?
    private let onReorderProjects: (([UUID]) -> Void)?
    private let shortcutHintsVisible: Bool

    public init(
        projects: [Project] = [],
        selectedProjectId: UUID? = nil,
        worktrees: [Worktree],
        windows: [RuntimeWindow],
        selectedWorktreeId: UUID?,
        selectedWindowId: String?,
        shortcutHintsVisible: Bool = false,
        onSelectProject: ((UUID) -> Void)? = nil,
        onSelectWorktree: @escaping (UUID) -> Void,
        onSelectWindow: @escaping (String) -> Void,
        onShowCreatePanel: (() -> Void)? = nil,
        onRemoveWorktree: ((UUID) -> Void)? = nil,
        onRemoveProject: ((UUID) -> Void)? = nil,
        onEditRemoteProject: ((UUID) -> Void)? = nil,
        onCloseWindow: ((String) -> Void)? = nil,
        onToggleCollapse: ((UUID) -> Void)? = nil,
        onAddProject: (() -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onOpenCommandPalette: (() -> Void)? = nil,
        onRequestPaneOutput: ((String, @escaping (String?) -> Void) -> Void)? = nil,
        onSendKeys: ((String, String) -> Void)? = nil,
        onUpdateProject: ((Project) -> Void)? = nil,
        onReorderProjects: (([UUID]) -> Void)? = nil
    ) {
        self.projects = projects
        self.selectedProjectId = selectedProjectId
        self.worktrees = worktrees
        self.windows = windows
        self.selectedWorktreeId = selectedWorktreeId
        self.selectedWindowId = selectedWindowId
        self.onSelectProject = onSelectProject
        self.onSelectWorktree = onSelectWorktree
        self.onSelectWindow = onSelectWindow
        self.onShowCreatePanel = onShowCreatePanel
        self.onRemoveWorktree = onRemoveWorktree
        self.onRemoveProject = onRemoveProject
        self.onEditRemoteProject = onEditRemoteProject
        self.onCloseWindow = onCloseWindow
        self.onToggleCollapse = onToggleCollapse
        self.onAddProject = onAddProject
        self.onOpenSettings = onOpenSettings
        self.onOpenCommandPalette = onOpenCommandPalette
        self.onRequestPaneOutput = onRequestPaneOutput
        self.onSendKeys = onSendKeys
        self.onUpdateProject = onUpdateProject
        self.onReorderProjects = onReorderProjects
        self.shortcutHintsVisible = shortcutHintsVisible
    }

    private struct ActiveWorktreeItem: Identifiable {
        let worktree: Worktree
        let projectName: String
        let agentName: String?

        var id: UUID { worktree.id }
    }

    private struct ActiveWorktreeStyle {
        let icon: String
        let color: Color
        let title: String
        let background: AnyShapeStyle
    }

    /// Count of agent windows needing attention across all worktrees.
    private var attentionCount: Int {
        windows.filter { $0.agentState == .waitingForInput || $0.agentState == .error }.count
    }

    private var runningCount: Int {
        windows.filter { $0.agentState == .running }.count
    }

    private var projectNamesById: [UUID: String] {
        Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) })
    }

    private var activeWorktreeItems: [ActiveWorktreeItem] {
        worktrees
            .filter { $0.status != .unavailable && $0.agentState != .none }
            .compactMap { worktree in
                guard let projectName = projectNamesById[worktree.projectId] else { return nil }
                let agentName = windows.first(where: {
                    $0.worktreeId == worktree.id && ($0.detectedAgent != nil || $0.agentState != .none)
                })?.detectedAgent
                return ActiveWorktreeItem(
                    worktree: worktree,
                    projectName: projectName,
                    agentName: agentName
                )
            }
            .sorted { lhs, rhs in
                let leftPriority = activeWorktreePriority(lhs.worktree.agentState)
                let rightPriority = activeWorktreePriority(rhs.worktree.agentState)
                if leftPriority != rightPriority {
                    return leftPriority < rightPriority
                }

                return (lhs.worktree.lastActiveAt ?? .distantPast) > (rhs.worktree.lastActiveAt ?? .distantPast)
            }
    }

    /// Projects sorted for display: pinned first, then unpinned, preserving array order within each group.
    private var sortedProjects: [Project] {
        projects.filter { $0.isFavorite } + projects.filter { !$0.isFavorite }
    }

    /// Global 1-based index for each window across all projects and worktrees.
    /// Iterates projects in display order so indices match ⌘1-9 quick jump.
    private var globalWindowIndices: [String: Int] {
        var result: [String: Int] = [:]
        var globalIndex = 1
        for project in sortedProjects where !project.isCollapsed {
            let projectWorktrees = worktrees
                .filter { $0.projectId == project.id && $0.status != .unavailable }
            for worktree in projectWorktrees {
                for window in allWindows(for: worktree) {
                    if globalIndex <= 9 {
                        result[window.tmuxWindowId] = globalIndex
                    }
                    globalIndex += 1
                }
            }
        }
        return result
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    summaryStrip
                    activeWorktreeSection
                    projectsSectionHeader

                    let sorted = sortedProjects
                    let firstUnpinnedIndex = sorted.firstIndex(where: { !$0.isFavorite })

                    ForEach(Array(sorted.enumerated()), id: \.element.id) { index, project in
                        if index > 0 {
                            if index == firstUnpinnedIndex {
                                // Separator between pinned and unpinned groups
                                Divider()
                                    .padding(.horizontal, MoriTokens.Spacing.xl)
                                    .padding(.vertical, MoriTokens.Spacing.xs)
                            } else {
                                Divider()
                                    .padding(.horizontal, MoriTokens.Spacing.xl)
                            }
                        }
                        projectSection(project)
                    }
                }
                .padding(.top, MoriTokens.Spacing.lg)
            }

            Spacer(minLength: 0)

            sidebarFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Rename Project", isPresented: Binding(
            get: { renamingProjectId != nil },
            set: { if !$0 { renamingProjectId = nil } }
        )) {
            TextField("Project name", text: $renameText)
            Button("Rename") {
                if let id = renamingProjectId,
                   var project = projects.first(where: { $0.id == id }),
                   !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    project.name = renameText.trimmingCharacters(in: .whitespaces)
                    onUpdateProject?(project)
                }
                renamingProjectId = nil
            }
            Button("Cancel", role: .cancel) {
                renamingProjectId = nil
            }
        }
    }

    // MARK: - Project Section

    @State private var hoveredProjectId: UUID?
    @State private var renamingProjectId: UUID?
    @State private var renameText: String = ""
    @State private var draggingProjectId: UUID?
    @State private var dropTargetProjectId: UUID?

    @ViewBuilder
    private func projectSection(_ project: Project) -> some View {
        // Section header: chevron + letter avatar + name + hover-reveal + count
        HStack(spacing: MoriTokens.Spacing.md) {
            Image(systemName: project.isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MoriTokens.Color.inactive)
                .frame(width: 10)

            ProjectLetterTile(project: project)

            Text(project.name)
                .font(MoriTokens.Font.projectTitle)
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            if project.isFavorite {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(MoriTokens.Color.inactive)
            }

            Spacer()

            let projectWorktreeCount = worktrees.filter { $0.projectId == project.id && $0.status != .unavailable }.count
            Text("\(projectWorktreeCount)")
                .font(MoriTokens.Font.caption)
                .foregroundStyle(MoriTokens.Color.inactive)

            if hoveredProjectId == project.id {
                HStack(spacing: MoriTokens.Spacing.sm) {
                    Menu {
                        projectActions(project)
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
                .transition(.opacity)
            }
        }
        .padding(.horizontal, MoriTokens.Spacing.xl)
        .padding(.top, 14)
        .padding(.bottom, MoriTokens.Spacing.sm)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            if dropTargetProjectId == project.id && draggingProjectId != project.id {
                Rectangle()
                    .fill(MoriTokens.Color.active)
                    .frame(height: 2)
                    .padding(.horizontal, MoriTokens.Spacing.xl)
            }
        }
        .animation(.easeInOut(duration: 0.14), value: shortcutHintsVisible)
        .draggable(project.id.uuidString) {
            Text(project.name)
                .font(MoriTokens.Font.projectTitle)
                .padding(.horizontal, MoriTokens.Spacing.lg)
                .padding(.vertical, MoriTokens.Spacing.sm)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: MoriTokens.Radius.small))
        }
        .dropDestination(for: String.self) { items, _ in
            guard let draggedIdStr = items.first,
                  let draggedId = UUID(uuidString: draggedIdStr),
                  draggedId != project.id else {
                dropTargetProjectId = nil
                return false
            }
            // Match the dropped project's pin state to the target group
            if var draggedProject = projects.first(where: { $0.id == draggedId }),
               draggedProject.isFavorite != project.isFavorite {
                draggedProject.isFavorite = project.isFavorite
                onUpdateProject?(draggedProject)
            }
            var ids = projects.map { $0.id }
            guard let fromIdx = ids.firstIndex(of: draggedId),
                  let toIdx = ids.firstIndex(of: project.id) else {
                dropTargetProjectId = nil
                return false
            }
            ids.remove(at: fromIdx)
            ids.insert(draggedId, at: toIdx)
            onReorderProjects?(ids)
            dropTargetProjectId = nil
            draggingProjectId = nil
            return true
        } isTargeted: { targeted in
            dropTargetProjectId = targeted ? project.id : nil
        }
        .onTapGesture {
            onToggleCollapse?(project.id)
            onSelectProject?(project.id)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredProjectId = hovering ? project.id : nil
            }
        }
        .contextMenu {
            projectActions(project)
        }

        if !project.isCollapsed {
            // Worktrees for this project
            let projectWorktrees = worktrees.filter { $0.projectId == project.id && $0.status != .unavailable }

            if projectWorktrees.isEmpty, project.id == selectedProjectId {
                Text("No worktrees")
                    .font(MoriTokens.Font.caption)
                    .foregroundStyle(MoriTokens.Color.muted)
                    .padding(.horizontal, MoriTokens.Spacing.xl)
                    .padding(.vertical, MoriTokens.Spacing.sm)
            }

            ForEach(projectWorktrees) { worktree in
                worktreeRow(worktree)
            }
        }
    }

    // MARK: - Worktree Row

    @ViewBuilder
    private func worktreeRow(_ worktree: Worktree) -> some View {
        let isSelected = worktree.id == selectedWorktreeId
        let worktreeWindows = allWindows(for: worktree)
        let detailWindows = visibleDetailWindows(for: worktree)
        let agentName = worktreeWindows.first(where: {
            $0.detectedAgent != nil || $0.agentState != .none
        })?.detectedAgent

        VStack(alignment: .leading, spacing: 0) {
            WorktreeRowView(
                worktree: worktree,
                agentName: agentName,
                isSelected: isSelected,
                onSelect: { onSelectWorktree(worktree.id) },
                onRemove: onRemoveWorktree.map { remove in { remove(worktree.id) } }
            )
            .contextMenu {
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

                if !worktree.isMainWorktree, let onRemove = onRemoveWorktree {
                    Divider()
                    Button(role: .destructive) {
                        onRemove(worktree.id)
                    } label: {
                        Label("Remove Worktree…", systemImage: "trash")
                    }
                }
            }

            // Show only the most relevant window details for the selected worktree.
            if isSelected, !detailWindows.isEmpty {
                TreeConnectorGroup(data: detailWindows) { window in
                    let globalIdx = globalWindowIndices[window.tmuxWindowId]
                    Group {
                        if window.detectedAgent != nil || window.agentState != .none {
                            AgentWindowRowView(
                                window: window,
                                projectName: projects.first(where: { $0.id == worktree.projectId })?.name ?? "",
                                worktreeName: worktree.name,
                                isSelected: isSelected && window.tmuxWindowId == selectedWindowId,
                                shortcutIndex: globalIdx,
                                shortcutHintsVisible: shortcutHintsVisible,
                                onSelect: { onSelectWindow(window.tmuxWindowId) },
                                onRequestPaneOutput: onRequestPaneOutput,
                                onSendKeys: onSendKeys
                            )
                        } else {
                            WindowRowView(
                                window: window,
                                isActive: isSelected && window.tmuxWindowId == selectedWindowId,
                                shortcutIndex: globalIdx,
                                shortcutHintsVisible: shortcutHintsVisible,
                                onSelect: { onSelectWindow(window.tmuxWindowId) },
                                onRequestPaneOutput: onRequestPaneOutput,
                                onSendKeys: onSendKeys
                            )
                        }
                    }
                    .contextMenu {
                        if let onCloseWindow {
                            Button(role: .destructive) {
                                onCloseWindow(window.tmuxWindowId)
                            } label: {
                                Label("Close Tab", systemImage: "xmark")
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, MoriTokens.Spacing.sm)
    }

    // MARK: - Helpers

    private func allWindows(for worktree: Worktree) -> [RuntimeWindow] {
        windows
            .filter { $0.worktreeId == worktree.id }
            .sorted { $0.tmuxWindowIndex < $1.tmuxWindowIndex }
    }

    private func visibleDetailWindows(for worktree: Worktree) -> [RuntimeWindow] {
        let all = allWindows(for: worktree)
        let relevant = all.filter(isRelevantDetailWindow)

        if !relevant.isEmpty {
            return relevant
        }

        return Array(all.prefix(1))
    }

    private func activeWorktreePriority(_ state: AgentState) -> Int {
        switch state {
        case .waitingForInput, .error: return 0
        case .running: return 1
        case .completed: return 2
        case .none: return 3
        }
    }

    @ViewBuilder
    private var projectsSectionHeader: some View {
        sectionHeader(title: String.localized("Projects")) {
            if let onAddProject {
                Button(action: onAddProject) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MoriTokens.Color.muted)
                }
                .buttonStyle(.plain)
                .help(String.localized("Add Project"))
            }
        }
        .padding(.top, MoriTokens.Spacing.lg)
    }

    @ViewBuilder
    private func projectActions(_ project: Project) -> some View {
        if !project.isCollapsed, onShowCreatePanel != nil {
            Button {
                onSelectProject?(project.id)
                onShowCreatePanel?()
            } label: {
                Label("New Workspace…", systemImage: "plus")
            }
        }

        let editors = EditorLauncher.installed
        if !editors.isEmpty {
            Divider()
            ForEach(editors) { editor in
                Button {
                    editor.open(path: project.repoRootPath)
                } label: {
                    Label("Open in \(editor.name)", systemImage: editor.icon)
                }
            }
        }

        Divider()

        Button {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.repoRootPath)
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }

        Divider()

        Button {
            renameText = project.name
            renamingProjectId = project.id
        } label: {
            Label("Rename Project…", systemImage: "pencil")
        }

        Button {
            var updated = project
            updated.isFavorite.toggle()
            onUpdateProject?(updated)
        } label: {
            if project.isFavorite {
                Label(String.localized("Unpin Project"), systemImage: "pin.slash")
            } else {
                Label(String.localized("Pin Project"), systemImage: "pin.fill")
            }
        }

        if case .ssh = (project.location ?? .local), let onEditRemoteProject {
            Button {
                onEditRemoteProject(project.id)
            } label: {
                Label("Update Remote Credentials…", systemImage: "key")
            }
        }

        if let onRemoveProject {
            Divider()
            Button(role: .destructive) {
                onRemoveProject(project.id)
            } label: {
                Label("Remove Project…", systemImage: "trash")
            }
        }
    }

    private func isRelevantDetailWindow(_ window: RuntimeWindow) -> Bool {
        window.tmuxWindowId == selectedWindowId
            || window.detectedAgent != nil
            || window.agentState != .none
            || window.badge != nil
            || window.hasUnreadOutput
    }

    /// Total worktree count across projects, excluding unavailable rows.
    private var availableWorktreeCount: Int {
        worktrees.filter { $0.status != .unavailable }.count
    }

    /// Quiet indicator strip: status dots + counts on the left, tree total on the right.
    /// Replaces the earlier Attention/Running tab-like chips so it stops competing with the list.
    @ViewBuilder
    private var summaryStrip: some View {
        HStack(spacing: MoriTokens.Spacing.xl) {
            summaryIndicator(
                text: "\(attentionCount) \(String.localized("waiting"))",
                tint: MoriTokens.Color.attention,
                isActive: attentionCount > 0
            )

            summaryIndicator(
                text: "\(runningCount) \(String.localized("running"))",
                tint: MoriTokens.Color.success,
                isActive: runningCount > 0
            )

            Spacer(minLength: 0)

            Text("\(availableWorktreeCount) \(String.localized("trees"))")
                .font(MoriTokens.Font.monoShortcut)
                .foregroundStyle(MoriTokens.Color.inactive)
        }
        .padding(.horizontal, MoriTokens.Spacing.xl)
        .padding(.bottom, MoriTokens.Spacing.md)
    }

    private func summaryIndicator(text: String, tint: Color, isActive: Bool) -> some View {
        HStack(spacing: MoriTokens.Spacing.sm) {
            Circle()
                .fill(isActive ? tint : MoriTokens.Color.inactive.opacity(MoriTokens.Opacity.medium))
                .frame(width: MoriTokens.Icon.dot, height: MoriTokens.Icon.dot)
                .shadow(color: isActive ? tint.opacity(0.55) : .clear, radius: 3)

            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(isActive ? Color.primary : MoriTokens.Color.muted)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var activeWorktreeSection: some View {
        if !activeWorktreeItems.isEmpty {
            VStack(alignment: .leading, spacing: MoriTokens.Spacing.sm) {
                sectionHeader(title: String.localized("Now")) {
                    Text("\(activeWorktreeItems.count)")
                        .font(MoriTokens.Font.caption)
                        .foregroundStyle(MoriTokens.Color.inactive)
                }

                VStack(spacing: MoriTokens.Spacing.sm) {
                    ForEach(activeWorktreeItems) { item in
                        activeWorktreeCard(item)
                    }
                }
                .padding(.horizontal, MoriTokens.Spacing.sm)
                .padding(.bottom, MoriTokens.Spacing.sm)
            }
        }
    }

    private func sectionHeader<Accessory: View>(
        title: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(MoriTokens.Color.muted)

            Spacer()

            accessory()
        }
        .padding(.horizontal, MoriTokens.Spacing.xl)
        .padding(.bottom, MoriTokens.Spacing.sm)
    }

private func activeWorktreeCard(_ item: ActiveWorktreeItem) -> some View {
        let style = activeWorktreeStyle(item.worktree.agentState)

        return Button {
            onSelectProject?(item.worktree.projectId)
            onSelectWorktree(item.worktree.id)
        } label: {
            HStack(alignment: .center, spacing: MoriTokens.Spacing.lg) {
                Image(systemName: style.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(style.color)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: MoriTokens.Spacing.xxs) {
                    HStack(spacing: MoriTokens.Spacing.sm) {
                        Text(item.worktree.name)
                            .font(MoriTokens.Font.rowTitle)
                            .lineLimit(1)
                        Text(style.title)
                            .font(MoriTokens.Font.caption)
                            .foregroundStyle(style.color)
                    }

                    Text(activeWorktreeSubtitle(for: item))
                        .font(MoriTokens.Font.caption)
                        .foregroundStyle(MoriTokens.Color.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, MoriTokens.Spacing.lg)
            .padding(.vertical, MoriTokens.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(style.background)
        .clipShape(RoundedRectangle(cornerRadius: MoriTokens.Radius.small))
    }

    private func activeWorktreeStyle(_ state: AgentState) -> ActiveWorktreeStyle {
        switch state {
        case .waitingForInput:
            return ActiveWorktreeStyle(
                icon: "exclamationmark.bubble.fill",
                color: MoriTokens.Color.attention,
                title: String.localized("Waiting"),
                background: AnyShapeStyle(MoriTokens.Color.attention.opacity(MoriTokens.Opacity.subtle))
            )
        case .error:
            return ActiveWorktreeStyle(
                icon: "xmark.circle.fill",
                color: MoriTokens.Color.error,
                title: String.localized("Error"),
                background: AnyShapeStyle(MoriTokens.Color.error.opacity(MoriTokens.Opacity.subtle))
            )
        case .running:
            return ActiveWorktreeStyle(
                icon: "bolt.fill",
                color: MoriTokens.Color.success,
                title: String.localized("Running"),
                background: AnyShapeStyle(MoriTokens.Color.success.opacity(MoriTokens.Opacity.subtle))
            )
        case .completed:
            return ActiveWorktreeStyle(
                icon: "checkmark.circle.fill",
                color: MoriTokens.Color.success,
                title: String.localized("Completed"),
                background: AnyShapeStyle(MoriTokens.Color.success.opacity(MoriTokens.Opacity.subtle))
            )
        case .none:
            return ActiveWorktreeStyle(
                icon: "circle.fill",
                color: MoriTokens.Color.muted,
                title: String.localized("Idle"),
                background: AnyShapeStyle(MoriTokens.Color.muted.opacity(MoriTokens.Opacity.subtle))
            )
        }
    }

    private func activeWorktreeSubtitle(for item: ActiveWorktreeItem) -> String {
        let agentText = item.agentName ?? String.localized("Agent")
        return "\(item.projectName) · \(agentText)"
    }


    // MARK: - Footer

    private var sidebarFooter: some View {
        SidebarFooterView(
            shortcutHintsVisible: shortcutHintsVisible,
            onAddProject: onAddProject,
            onOpenCommandPalette: onOpenCommandPalette,
            onOpenSettings: onOpenSettings,
            horizontalDividerPadding: MoriTokens.Spacing.xl
        )
    }
}

// MARK: - Tree Connector

/// Draws L-shaped tree connector branches (├── for middle rows, └── for last row).
/// Each child row gets a horizontal branch from the vertical line.
struct TreeConnectorGroup<Data: RandomAccessCollection, Row: View>: View where Data.Element: Identifiable {
    let data: Data
    let row: (Data.Element) -> Row

    init(data: Data, @ViewBuilder row: @escaping (Data.Element) -> Row) {
        self.data = data
        self.row = row
    }

    /// Horizontal offset to align with center of 28pt icon box (row padding + half box).
    private let lineX: CGFloat = 24

    /// Length of horizontal branch from vertical line to content.
    private let branchLength: CGFloat = 10

    private let lineColor = Color.primary.opacity(0.10)

    var body: some View {
        let items = Array(data)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let isLast = index == items.count - 1
                HStack(alignment: .top, spacing: 0) {
                    // Branch connector: vertical segment + horizontal arm
                    Canvas { ctx, size in
                        let midX: CGFloat = 0.5
                        let midY = size.height / 2

                        var path = Path()
                        // Vertical segment: from top to midY (last) or full height (middle)
                        path.move(to: CGPoint(x: midX, y: 0))
                        path.addLine(to: CGPoint(x: midX, y: isLast ? midY : size.height))
                        // Horizontal arm from midY
                        path.move(to: CGPoint(x: midX, y: midY))
                        path.addLine(to: CGPoint(x: branchLength, y: midY))

                        ctx.stroke(path, with: .color(lineColor), lineWidth: 1)
                    }
                    .frame(width: branchLength)
                    .padding(.leading, lineX)

                    row(item)
                }
            }
        }
    }
}
