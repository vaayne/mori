import SwiftUI
import AppKit
import MoriCore

/// Conductor-style sidebar: full-width repo sections separated by hairlines,
/// each expanding into a "+ New workspace" row and two-line workspace rows
/// (branch + diff badge, then worktree name · status + ⌘N). A bottom bar holds
/// "Add repository" and settings.
public struct WorktreeSidebarView: View {
    private let projects: [Project]
    private let selectedProjectId: UUID?
    private let worktrees: [Worktree]
    private let windows: [RuntimeWindow]
    private let panes: [RuntimePane]
    private let selectedWorktreeId: UUID?
    private let selectedWindowId: String?
    private let onSelectProject: ((UUID) -> Void)?
    private let onSelectWorktree: (UUID) -> Void
    private let onSelectWindow: (String) -> Void
    private let onSelectPane: ((String) -> Void)?
    private let onShowCreatePanel: (() -> Void)?
    private let onRemoveWorktree: ((UUID) -> Void)?
    private let onRemoveProject: ((UUID) -> Void)?
    private let onImportWorktrees: ((UUID) -> Void)?
    private let onEditRemoteProject: ((UUID) -> Void)?
    private let onCloseWindow: ((String) -> Void)?
    private let onToggleCollapse: ((UUID) -> Void)?
    private let onAddProject: (() -> Void)?
    private let onOpenSettings: (() -> Void)?
    private let onRequestPaneOutput: ((String, @escaping (String?) -> Void) -> Void)?
    private let onSendKeys: ((String, String) -> Void)?
    private let onUpdateProject: ((Project) -> Void)?
    private let onReorderProjects: (([UUID]) -> Void)?
    /// Live PR snapshots keyed by worktree id; only the selected row renders one.
    private let pullRequests: [UUID: PullRequestInfo]
    private let shortcutHintsVisible: Bool

    @State private var hoveredProjectId: UUID?
    @State private var hoveredWorktreeId: UUID?
    @State private var renamingProjectId: UUID?
    @State private var renameText = ""
    @State private var draggingProjectId: UUID?
    @State private var dropTargetProjectId: UUID?
    /// Worktrees whose tmux windows (the third level) are expanded. Collapsed by
    /// default so the sidebar reads as two levels: project → worktree.
    @State private var expandedWorktrees: Set<UUID> = []

    public init(
        projects: [Project] = [], selectedProjectId: UUID? = nil, worktrees: [Worktree], windows: [RuntimeWindow], panes: [RuntimePane] = [], selectedWorktreeId: UUID?, selectedWindowId: String?, shortcutHintsVisible: Bool = false, onSelectProject: ((UUID) -> Void)? = nil, onSelectWorktree: @escaping (UUID) -> Void, onSelectWindow: @escaping (String) -> Void, onSelectPane: ((String) -> Void)? = nil, onShowCreatePanel: (() -> Void)? = nil, onRemoveWorktree: ((UUID) -> Void)? = nil, onRemoveProject: ((UUID) -> Void)? = nil, onImportWorktrees: ((UUID) -> Void)? = nil, onEditRemoteProject: ((UUID) -> Void)? = nil, onCloseWindow: ((String) -> Void)? = nil, onToggleCollapse: ((UUID) -> Void)? = nil, onAddProject: (() -> Void)? = nil, onOpenSettings: (() -> Void)? = nil, onRequestPaneOutput: ((String, @escaping (String?) -> Void) -> Void)? = nil, onSendKeys: ((String, String) -> Void)? = nil, onUpdateProject: ((Project) -> Void)? = nil, onReorderProjects: (([UUID]) -> Void)? = nil, pullRequests: [UUID: PullRequestInfo] = [:]
    ) {
        self.projects = projects; self.selectedProjectId = selectedProjectId; self.worktrees = worktrees; self.windows = windows; self.panes = panes; self.selectedWorktreeId = selectedWorktreeId; self.selectedWindowId = selectedWindowId; self.onSelectProject = onSelectProject; self.onSelectWorktree = onSelectWorktree; self.onSelectWindow = onSelectWindow; self.onSelectPane = onSelectPane; self.onShowCreatePanel = onShowCreatePanel; self.onRemoveWorktree = onRemoveWorktree; self.onRemoveProject = onRemoveProject; self.onImportWorktrees = onImportWorktrees; self.onEditRemoteProject = onEditRemoteProject; self.onCloseWindow = onCloseWindow; self.onToggleCollapse = onToggleCollapse; self.onAddProject = onAddProject; self.onOpenSettings = onOpenSettings; self.onRequestPaneOutput = onRequestPaneOutput; self.onSendKeys = onSendKeys; self.onUpdateProject = onUpdateProject; self.onReorderProjects = onReorderProjects; self.pullRequests = pullRequests; self.shortcutHintsVisible = shortcutHintsVisible
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let home = homeProject {
                        homeRow(home)
                    }
                    ForEach(Array(sortedProjects.enumerated()), id: \.element.id) { index, project in
                        projectSection(project, isFirst: index == 0 && homeProject == nil)
                    }
                }
                .padding(.bottom, MoriTokens.Spacing.md)
            }
            .scrollIndicators(.never)
            agentSummaryStrip
            sidebarFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Rename Project", isPresented: Binding(get: { renamingProjectId != nil }, set: { if !$0 { renamingProjectId = nil } })) {
            TextField("Project name", text: $renameText)
            Button("Rename") { renameProject() }
            Button("Cancel", role: .cancel) { renamingProjectId = nil }
        }
    }

    // MARK: - Home row

    /// The $HOME workspace as a single Conductor-style "Home" row: no workspace
    /// list, no "+ New workspace" — one click drops into a session at $HOME for
    /// tasks that don't belong to any repository.
    @ViewBuilder
    private func homeRow(_ project: Project) -> some View {
        let worktree = visibleWorktrees(for: project).first
        let selected = worktree != nil && worktree?.id == selectedWorktreeId
        let agg = aggregateState(for: project)
        Button {
            onSelectProject?(project.id)
            if let worktree { onSelectWorktree(worktree.id) }
        } label: {
            HStack(spacing: MoriTokens.Spacing.md) {
                Group {
                    if let worktree, worktree.agentState == .running {
                        AgentWorkingIcon(asset: workingAgentAsset(worktree),
                                         color: selected ? Color.primary : MoriTokens.Color.success)
                    } else {
                        Image(systemName: "house")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(selected ? Color.primary : MoriTokens.Color.muted)
                    }
                }
                .frame(width: 15)
                Text(project.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(selected ? 1 : 0.85))
                Spacer(minLength: 0)
                if agg == .waiting || agg == .error {
                    Circle().fill(agg == .error ? MoriTokens.Color.error : MoriTokens.Color.attention).frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, MoriTokens.Spacing.md)
            .padding(.vertical, MoriTokens.Spacing.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: MoriTokens.Radius.small)
                .fill(selected ? Color.primary.opacity(MoriTokens.Opacity.subtle) : Color.clear)
        )
        .padding(.horizontal, MoriTokens.Spacing.md)
        .padding(.top, MoriTokens.Spacing.sm)
        .contextMenu { projectActions(project, allowNewWorkspace: false) }
    }

    // MARK: - Project section

    private func projectSection(_ project: Project, isFirst: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isFirst {
                Rectangle().fill(Color.primary.opacity(MoriTokens.Opacity.subtle)).frame(height: 1)
            }
            projectHeader(project)
            if !project.isCollapsed {
                newWorkspaceRow(project)
                worktreesGroup(project)
                    .padding(.bottom, MoriTokens.Spacing.md)
            }
        }
        .overlay(alignment: .top) { if dropTargetProjectId == project.id && draggingProjectId != project.id { Rectangle().fill(MoriTokens.Color.active).frame(height: 2).padding(.horizontal, MoriTokens.Spacing.lg) } }
        .draggable(project.id.uuidString) { Text(project.name).padding().background(.regularMaterial) }
        .dropDestination(for: String.self) { items, _ in reorder(dragged: items.first, before: project) } isTargeted: { dropTargetProjectId = $0 ? project.id : nil }
        .onHover { hoveredProjectId = $0 ? project.id : nil }
        .contextMenu { projectActions(project) }
    }

    /// Repo name with a trailing chevron, Conductor-style. Tap toggles the
    /// section open/closed; an aggregate dot flags attention while collapsed.
    private func projectHeader(_ project: Project) -> some View {
        let agg = aggregateState(for: project)
        return HStack(spacing: MoriTokens.Spacing.md) {
            Text(project.name)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(project.id == selectedProjectId ? 1 : 0.85))
                .lineLimit(1)
            if project.isFavorite { Image(systemName: "pin.fill").font(.system(size: 9, weight: .semibold)).foregroundStyle(MoriTokens.Color.inactive) }
            Spacer(minLength: 0)
            if project.isCollapsed, agg == .waiting || agg == .error {
                Circle().fill(agg == .error ? MoriTokens.Color.error : MoriTokens.Color.attention).frame(width: 7, height: 7)
            }
            Image(systemName: project.isCollapsed ? "chevron.right" : "chevron.down")
                .font(MoriTokens.Font.sidebarChevron)
                .foregroundStyle(MoriTokens.Color.muted)
        }
        .padding(.horizontal, MoriTokens.Spacing.xl)
        .padding(.top, MoriTokens.Sidebar.projectHeaderTop)
        .padding(.bottom, MoriTokens.Spacing.lg)
        .contentShape(Rectangle())
        .onTapGesture { onToggleCollapse?(project.id); onSelectProject?(project.id) }
    }

    /// "+ New workspace" with a trailing overflow menu carrying project actions.
    @ViewBuilder
    private func newWorkspaceRow(_ project: Project) -> some View {
        if onShowCreatePanel != nil {
            HStack(spacing: MoriTokens.Spacing.md) {
                Button { onSelectProject?(project.id); onShowCreatePanel?() } label: {
                    HStack(spacing: MoriTokens.Spacing.md) {
                        Image(systemName: "plus").font(.system(size: 11, weight: .medium)).frame(width: 15)
                        Text("New workspace").font(.system(size: 13))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(MoriTokens.Color.muted)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Menu { projectActions(project) } label: {
                    Image(systemName: "ellipsis").font(MoriTokens.Font.sidebarAccessory).foregroundStyle(MoriTokens.Color.muted)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
                .frame(width: MoriTokens.Size.sidebarAccessory)
            }
            .padding(.horizontal, MoriTokens.Spacing.xl)
            .padding(.vertical, MoriTokens.Spacing.sm)
        }
    }

    @ViewBuilder
    private func worktreesGroup(_ project: Project) -> some View {
        let all = visibleWorktrees(for: project)
        VStack(alignment: .leading, spacing: 1) {
            ForEach(all) { worktree in
                worktreeRow(worktree)
                if expandedWorktrees.contains(worktree.id) {
                    ForEach(allWindows(for: worktree)) { window in
                        WindowRowView(window: window, isActive: window.tmuxWindowId == selectedWindowId, shortcutIndex: nil, shortcutHintsVisible: shortcutHintsVisible, onSelect: { onSelectWindow(window.tmuxWindowId) }, onRequestPaneOutput: onRequestPaneOutput, onSendKeys: onSendKeys)
                            .padding(.leading, MoriTokens.Spacing.xxl)
                    }
                }
            }
        }
        .padding(.horizontal, MoriTokens.Spacing.md)
    }

    // MARK: - Worktree row

    /// Two-line Conductor-style row. Line 1: branch glyph (or the working
    /// agent's breathing brand glyph) + branch name + diff badge. Line 2:
    /// worktree name · status + quick-jump ⌘N.
    private func worktreeRow(_ worktree: Worktree) -> some View {
        let selected = worktree.id == selectedWorktreeId
        let hovered = hoveredWorktreeId == worktree.id
        let wins = allWindows(for: worktree)
        let expanded = expandedWorktrees.contains(worktree.id)
        let title = worktree.branch ?? worktree.name
        return Button { onSelectWorktree(worktree.id) } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: MoriTokens.Spacing.md) {
                    Group {
                        if worktree.agentState == .running {
                            AgentWorkingIcon(asset: workingAgentAsset(worktree),
                                             color: selected ? Color.primary : MoriTokens.Color.success)
                        } else {
                            Image(systemName: worktreeGlyph(worktree))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(worktreeIconColor(worktree, selected: selected))
                        }
                    }
                    .frame(width: 15)
                    Text(title)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(worktreeNameColor(worktree, selected: selected))
                        .lineLimit(1)
                    Spacer(minLength: MoriTokens.Spacing.sm)
                    if wins.count >= 2 {
                        windowChip(count: wins.count, expanded: expanded, selected: selected, alert: hiddenWindowAlert(wins, expanded: expanded)) { toggle(&expandedWorktrees, worktree.id) }
                    }
                    diffBadge(worktree)
                }
                secondLine(worktree, title: title)
            }
            .padding(.horizontal, MoriTokens.Spacing.md)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: MoriTokens.Radius.small)
                .fill(selected ? Color.primary.opacity(MoriTokens.Opacity.subtle) : (hovered ? Color.primary.opacity(MoriTokens.Opacity.quiet) : Color.clear))
        )
        .onHover { hoveredWorktreeId = $0 ? worktree.id : nil }
        .contextMenu { WorktreeContextActions(worktree: worktree, pullRequest: pullRequests[worktree.id], onRemove: onRemoveWorktree.map { remove in { remove(worktree.id) } }) }
    }

    /// `+N -M` lines vs the project's base branch, in a quiet bordered pill.
    @ViewBuilder
    private func diffBadge(_ worktree: Worktree) -> some View {
        if worktree.additions > 0 || worktree.deletions > 0 {
            HStack(spacing: MoriTokens.Spacing.sm) {
                if worktree.additions > 0 {
                    Text(verbatim: "+\(compactCount(worktree.additions))").foregroundStyle(MoriTokens.Color.success)
                }
                if worktree.deletions > 0 {
                    Text(verbatim: "-\(compactCount(worktree.deletions))").foregroundStyle(MoriTokens.Color.error)
                }
            }
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: MoriTokens.Radius.badge + 1)
                    .stroke(Color.primary.opacity(MoriTokens.Opacity.light), lineWidth: 1)
            )
        }
    }

    /// Keeps the diff badge narrow on huge branches: 65031 reads as "65k".
    private func compactCount(_ n: Int) -> String {
        n >= 10_000 ? "\(n / 1000)k" : "\(n)"
    }

    /// Worktree name (when it differs from the branch title) · status, with the
    /// quick-jump shortcut on the right. The status word is the row's one loud
    /// element: agent activity first, then merge readiness, then quiet time.
    @ViewBuilder
    private func secondLine(_ worktree: Worktree, title: String) -> some View {
        let status = statusText(worktree)
        let shortcut = worktreeShortcutIndices[worktree.id]
        if worktree.name != title || status != nil || shortcut != nil {
            HStack(spacing: MoriTokens.Spacing.sm) {
                if worktree.name != title {
                    Text(worktree.name).foregroundStyle(MoriTokens.Color.muted).lineLimit(1)
                    if status != nil { Text("·").foregroundStyle(MoriTokens.Color.muted) }
                }
                if let status {
                    Text(status.text).foregroundStyle(status.color).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let shortcut {
                    Text("⌘\(shortcut)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(shortcutHintsVisible ? Color.primary.opacity(0.8) : MoriTokens.Color.inactive)
                }
            }
            .font(.system(size: 11.5))
            .padding(.leading, 15 + MoriTokens.Spacing.md)
        }
    }

    private func statusText(_ w: Worktree) -> (text: String, color: Color)? {
        switch w.agentState {
        case .running: return (String.localized("Working…"), MoriTokens.Color.success)
        case .waitingForInput: return (String.localized("Needs input"), MoriTokens.Color.attention)
        case .error: return (String.localized("Agent error"), MoriTokens.Color.error)
        case .completed, .none: break
        }
        if w.hasMergeConflicts == true { return (String.localized("Merge conflicts"), MoriTokens.Color.warning) }
        if w.hasMergeConflicts == false, w.additions + w.deletions > 0, !w.hasUncommittedChanges {
            return (String.localized("Ready to merge"), MoriTokens.Color.success)
        }
        if let time = relativeTime(w.lastActiveAt) { return (time, MoriTokens.Color.inactive) }
        return nil
    }

    /// The main/master checkout and linked worktrees read as different shapes; a
    /// detached HEAD gets its own dotted glyph. Colour stays quiet unless an agent
    /// is live (error / waiting / running), so the icon doubles as a status cue.
    private func worktreeGlyph(_ w: Worktree) -> String {
        if w.isDetached || w.branch == nil { return "circle.dotted" }
        return isPrimaryWorktree(w) ? "arrow.triangle.branch" : "point.3.connected.trianglepath.dotted"
    }

    private func isPrimaryWorktree(_ w: Worktree) -> Bool {
        w.branch == "main" || w.branch == "master"
    }

    private func worktreeIconColor(_ w: Worktree, selected: Bool) -> Color {
        if selected { return Color.primary }
        switch w.agentState {
        case .error: return MoriTokens.Color.error
        case .waitingForInput: return MoriTokens.Color.attention
        case .running: return MoriTokens.Color.success
        case .completed, .none: return MoriTokens.Color.muted
        }
    }

    private func windowChip(count: Int, expanded: Bool, selected: Bool, alert: Color?, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: 2) {
                Text("\(count)")
                Image(systemName: "chevron.down").rotationEffect(.degrees(expanded ? 0 : -90))
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(selected ? Color.primary.opacity(0.85) : MoriTokens.Color.muted)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(MoriTokens.Color.muted.opacity(MoriTokens.Opacity.light)))
            .overlay(alignment: .topTrailing) { if let alert, !expanded { Circle().fill(alert).frame(width: 5, height: 5).offset(x: 2, y: -2) } }
        }.buttonStyle(.plain)
    }

    private func worktreeNameColor(_ w: Worktree, selected: Bool) -> Color {
        if selected { return Color.primary }
        return (w.status == .active || w.agentState != .none) ? Color.primary.opacity(0.9) : MoriTokens.Color.muted
    }

    private func relativeTime(_ date: Date?) -> String? {
        guard let date else { return nil }
        let s = Int(-date.timeIntervalSinceNow)
        if s < 60 { return String.localized("just now") }
        if s < 3600 { return String(format: String.localized("%lldm ago"), s / 60) }
        if s < 86400 { return String(format: String.localized("%lldh ago"), s / 3600) }
        if s < 2_592_000 { return String(format: String.localized("%lldd ago"), s / 86400) }
        return String(format: String.localized("%lldmo ago"), s / 2_592_000)
    }

    // MARK: - Footer

    /// Aggregate strip above the footer: one dot + count per agent state
    /// (waiting / running / error), dimmed when zero. Clicking a state lists
    /// its workspaces — pick one to jump straight to it. Falls back to dots +
    /// counts (no words) when the sidebar is too narrow for the full labels.
    private var agentSummaryStrip: some View {
        ViewThatFits(in: .horizontal) {
            summaryStripContent(showWords: true)
            summaryStripContent(showWords: false)
        }
        .padding(.horizontal, MoriTokens.Spacing.xl)
        .padding(.vertical, MoriTokens.Spacing.sm)
    }

    private func summaryStripContent(showWords: Bool) -> some View {
        let ordered = worktreesInDisplayOrder
        let waiting = ordered.filter { $0.agentState == .waitingForInput }
        let running = ordered.filter { $0.agentState == .running }
        let errors = ordered.filter { $0.agentState == .error }
        return HStack(spacing: MoriTokens.Spacing.xl) {
            summaryIndicator(candidates: waiting, state: .waitingForInput, word: showWords ? String.localized("waiting") : nil, tint: MoriTokens.Color.attention)
            summaryIndicator(candidates: running, state: .running, word: showWords ? String.localized("running") : nil, tint: MoriTokens.Color.success)
            summaryIndicator(candidates: errors, state: .error, word: showWords ? String.localized("error") : nil, tint: MoriTokens.Color.error)
            Spacer(minLength: 0)
        }
    }

    private func summaryIndicator(candidates: [Worktree], state: AgentState, word: String?, tint: Color) -> some View {
        let count = candidates.count
        return Menu {
            ForEach(candidates) { worktree in
                Button { jump(to: worktree, state: state) } label: {
                    Text(verbatim: menuTitle(for: worktree))
                }
            }
        } label: {
            HStack(spacing: MoriTokens.Spacing.sm) {
                Circle()
                    .fill(count > 0 ? tint : MoriTokens.Color.inactive.opacity(MoriTokens.Opacity.medium))
                    .frame(width: MoriTokens.Icon.dot, height: MoriTokens.Icon.dot)
                Text(verbatim: word.map { "\(count) \($0)" } ?? "\(count)")
                    .font(MoriTokens.Font.monoSmall)
                    .foregroundStyle(count > 0 ? Color.primary.opacity(0.85) : MoriTokens.Color.inactive)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        // .borderlessButton flattens the custom label to monochrome text,
        // losing the status dot's tint; .button + .plain keeps the view as-is.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .disabled(count == 0)
    }

    /// "project · branch" so same-named branches across repos stay distinguishable.
    private func menuTitle(for worktree: Worktree) -> String {
        let title = worktree.branch ?? worktree.name
        guard let project = projects.first(where: { $0.id == worktree.projectId }) else { return title }
        return "\(project.name) · \(title)"
    }

    /// Select the workspace and land on the tmux window whose agent is in `state`.
    private func jump(to worktree: Worktree, state: AgentState) {
        onSelectWorktree(worktree.id)
        if let window = allWindows(for: worktree).first(where: { $0.agentState == state }) {
            onSelectWindow(window.tmuxWindowId)
        }
    }

    /// All jumpable worktrees in sidebar display order (Home first, then repo
    /// sections pinned-first) — including collapsed projects, since an agent
    /// that needs you shouldn't hide behind a folded section.
    private var worktreesInDisplayOrder: [Worktree] {
        let projectOrder = [homeProject].compactMap { $0 } + sortedProjects
        return projectOrder.flatMap { visibleWorktrees(for: $0) }
    }

    private var sidebarFooter: some View {
        HStack(spacing: MoriTokens.Spacing.md) {
            if let onAddProject {
                Button(action: onAddProject) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.badge.plus").font(.system(size: 12, weight: .medium))
                            Text("Add repository").font(.system(size: 12.5)).lineLimit(1)
                        }
                        Image(systemName: "folder.badge.plus").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(MoriTokens.Color.muted)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(String.localized("Add Project"))
            }
            Spacer()
            if let onOpenSettings {
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundStyle(MoriTokens.Color.muted)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(String.localized("Settings"))
            }
        }
        .padding(.horizontal, MoriTokens.Spacing.xl)
        .padding(.vertical, MoriTokens.Spacing.lg)
        .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(MoriTokens.Opacity.subtle)).frame(height: 1) }
    }

    // MARK: - Derived data

    private func toggle(_ set: inout Set<UUID>, _ id: UUID) { if set.contains(id) { set.remove(id) } else { set.insert(id) } }

    /// Colour for a hidden window that needs you (error wins over waiting), or nil
    /// when nothing is hidden — drives the dot on the worktree's window chip.
    private func hiddenWindowAlert(_ windows: [RuntimeWindow], expanded: Bool) -> Color? {
        guard !expanded, windows.count >= 2 else { return nil }
        if windows.contains(where: { $0.badge == .error || $0.agentState == .error }) { return MoriTokens.Color.error }
        if windows.contains(where: { $0.badge == .waiting || $0.agentState == .waitingForInput }) { return MoriTokens.Color.attention }
        return nil
    }

    private var homeProject: Project? { projects.first(where: \.isHomeWorkspace) }
    private var sortedProjects: [Project] { let repos = projects.filter { !$0.isHomeWorkspace }; return repos.filter(\.isFavorite) + repos.filter { !$0.isFavorite } }
    private func visibleWorktrees(for project: Project) -> [Worktree] { worktrees.filter { $0.projectId == project.id && $0.status != .unavailable } }
    private func aggregateState(for project: Project) -> SidebarStatus { let ws = visibleWorktrees(for: project); if ws.contains(where: { $0.agentState == .error }) { return .error }; if ws.contains(where: { $0.agentState == .waitingForInput }) { return .waiting }; if ws.contains(where: { $0.agentState == .running }) { return .running }; return .idle }
    private func allWindows(for worktree: Worktree) -> [RuntimeWindow] { windows.filter { $0.worktreeId == worktree.id }.sorted { $0.tmuxWindowIndex < $1.tmuxWindowIndex } }

    /// Bundled template-icon name for the coding agent working in this worktree,
    /// resolved from the detected process name; nil falls back to a generic glyph.
    private func workingAgentAsset(_ worktree: Worktree) -> String? {
        let wins = allWindows(for: worktree)
        let detected = wins.first { $0.agentState == .running && $0.detectedAgent != nil }?.detectedAgent
            ?? wins.compactMap(\.detectedAgent).first
        guard let d = detected?.lowercased() else { return nil }
        if d.contains("claude") { return "agent-claude" }
        if d.contains("codex") { return "agent-codex" }
        if d == "pi" || d.hasPrefix("pi-") || d.hasPrefix("pi.") { return "agent-pi" }
        return nil
    }

    /// ⌘1–9 across all visible worktrees in display order — Conductor's
    /// per-workspace quick jump. Must stay in sync with
    /// `WorkspaceManager.quickJump` ordering.
    private var worktreeShortcutIndices: [UUID: Int] { var result: [UUID: Int] = [:]; var i = 1; for project in sortedProjects where !project.isCollapsed { for worktree in visibleWorktrees(for: project) { if i <= 9 { result[worktree.id] = i }; i += 1 } }; return result }
    private func renameProject() { if let id = renamingProjectId, var project = projects.first(where: { $0.id == id }), !renameText.trimmingCharacters(in: .whitespaces).isEmpty { project.name = renameText.trimmingCharacters(in: .whitespaces); onUpdateProject?(project) }; renamingProjectId = nil }
    private func reorder(dragged: String?, before project: Project) -> Bool { guard let s = dragged, let draggedId = UUID(uuidString: s), draggedId != project.id else { dropTargetProjectId = nil; return false }; if var draggedProject = projects.first(where: { $0.id == draggedId }), draggedProject.isFavorite != project.isFavorite { draggedProject.isFavorite = project.isFavorite; onUpdateProject?(draggedProject) }; var ids = projects.map(\.id); guard let from = ids.firstIndex(of: draggedId), let to = ids.firstIndex(of: project.id) else { return false }; ids.remove(at: from); ids.insert(draggedId, at: to); onReorderProjects?(ids); dropTargetProjectId = nil; draggingProjectId = nil; return true }

    @ViewBuilder private func projectActions(_ project: Project, allowNewWorkspace: Bool = true) -> some View {
        if allowNewWorkspace, !project.isCollapsed, onShowCreatePanel != nil { Button { onSelectProject?(project.id); onShowCreatePanel?() } label: { Label("New Workspace…", systemImage: "plus") } }
        let editors = EditorLauncher.installed; if !editors.isEmpty { Divider(); ForEach(editors) { editor in Button { editor.open(path: project.repoRootPath) } label: { Label("Open in \(editor.name)", systemImage: editor.icon) } } }
        Divider(); Button { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.repoRootPath) } label: { Label("Reveal in Finder", systemImage: "folder") }
        Divider(); Button { renameText = project.name; renamingProjectId = project.id } label: { Label("Rename Project…", systemImage: "pencil") }
        Button { var updated = project; updated.isFavorite.toggle(); onUpdateProject?(updated) } label: { Label(project.isFavorite ? String.localized("Unpin Project") : String.localized("Pin Project"), systemImage: project.isFavorite ? "pin.slash" : "pin.fill") }
        if let onImportWorktrees, project.gitCommonDir != project.repoRootPath { Button { onImportWorktrees(project.id) } label: { Label("Import Existing Worktrees", systemImage: "square.and.arrow.down") } }
        if case .ssh = (project.location ?? .local), let onEditRemoteProject { Button { onEditRemoteProject(project.id) } label: { Label("Update Remote Credentials…", systemImage: "key") } }
        if let onRemoveProject { Divider(); Button(role: .destructive) { onRemoveProject(project.id) } label: { Label("Remove Project…", systemImage: "trash") } }
    }
}

private enum SidebarStatus { case waiting, running, idle, error }

/// The working cue in a worktree row's leading slot: the agent's own brand glyph
/// (template-tinted to the running colour), or a generic AI glyph when the agent
/// is unknown. Breathes to signal live activity — asset images can't carry an SF
/// `symbolEffect`, so the pulse is a plain opacity animation.
private struct AgentWorkingIcon: View {
    let asset: String?
    let color: Color
    @State private var breathing = false
    var body: some View {
        Group {
            if let asset, let image = AgentIconLoader.image(named: asset) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .foregroundStyle(color)
        .opacity(breathing ? 0.45 : 1)
        .animation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true), value: breathing)
        .onAppear { breathing = true }
    }
}

/// Loads bundled agent SVGs as tintable template images. SwiftPM doesn't compile
/// asset catalogs, so the glyphs ship as loose SVG files read straight off the
/// module bundle via `NSImage` (macOS 13+ renders SVG natively) and cached.
@MainActor
private enum AgentIconLoader {
    private static var cache: [String: NSImage] = [:]
    static func image(named name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        guard let url = Bundle.module.url(forResource: name, withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        cache[name] = image
        return image
    }
}
