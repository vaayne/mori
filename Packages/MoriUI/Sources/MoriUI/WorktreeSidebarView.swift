import SwiftUI
import MoriCore

/// Sidebar as a calm project tree: a flat list of projects (folder glyph + name),
/// each expanding inline into a "Worktrees" group of branch-named rows. No
/// attention-inbox sections — state surfaces as quiet dots on the rows themselves.
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
    private let onRequestPaneOutput: ((String, @escaping (String?) -> Void) -> Void)?
    private let onSendKeys: ((String, String) -> Void)?
    private let onUpdateProject: ((Project) -> Void)?
    private let onReorderProjects: (([UUID]) -> Void)?
    /// Live PR snapshots keyed by worktree id; only the selected row renders one.
    private let pullRequests: [UUID: PullRequestInfo]
    private let shortcutHintsVisible: Bool
    private let isSidebarCollapsed: Bool

    /// How many worktree rows show before a project collapses the rest behind
    /// "Show N more" — keeps long projects from flooding the list.
    private let worktreeLimit = 6

    @State private var hoveredProjectId: UUID?
    @State private var renamingProjectId: UUID?
    @State private var renameText = ""
    @State private var draggingProjectId: UUID?
    @State private var dropTargetProjectId: UUID?
    /// Projects whose worktree list is fully expanded past `worktreeLimit`.
    @State private var expandedProjects: Set<UUID> = []
    /// Worktrees whose tmux windows (the third level) are expanded. Collapsed by
    /// default so the sidebar reads as two levels: project → worktree.
    @State private var expandedWorktrees: Set<UUID> = []

    public init(
        projects: [Project] = [], selectedProjectId: UUID? = nil, worktrees: [Worktree], windows: [RuntimeWindow], panes: [RuntimePane] = [], selectedWorktreeId: UUID?, selectedWindowId: String?, shortcutHintsVisible: Bool = false, onSelectProject: ((UUID) -> Void)? = nil, onSelectWorktree: @escaping (UUID) -> Void, onSelectWindow: @escaping (String) -> Void, onSelectPane: ((String) -> Void)? = nil, onShowCreatePanel: (() -> Void)? = nil, onRemoveWorktree: ((UUID) -> Void)? = nil, onRemoveProject: ((UUID) -> Void)? = nil, onImportWorktrees: ((UUID) -> Void)? = nil, onEditRemoteProject: ((UUID) -> Void)? = nil, onCloseWindow: ((String) -> Void)? = nil, onToggleCollapse: ((UUID) -> Void)? = nil, onAddProject: (() -> Void)? = nil, onRequestPaneOutput: ((String, @escaping (String?) -> Void) -> Void)? = nil, onSendKeys: ((String, String) -> Void)? = nil, onUpdateProject: ((Project) -> Void)? = nil, onReorderProjects: (([UUID]) -> Void)? = nil, pullRequests: [UUID: PullRequestInfo] = [:], isSidebarCollapsed: Bool = false
    ) {
        self.projects = projects; self.selectedProjectId = selectedProjectId; self.worktrees = worktrees; self.windows = windows; self.panes = panes; self.selectedWorktreeId = selectedWorktreeId; self.selectedWindowId = selectedWindowId; self.onSelectProject = onSelectProject; self.onSelectWorktree = onSelectWorktree; self.onSelectWindow = onSelectWindow; self.onSelectPane = onSelectPane; self.onShowCreatePanel = onShowCreatePanel; self.onRemoveWorktree = onRemoveWorktree; self.onRemoveProject = onRemoveProject; self.onImportWorktrees = onImportWorktrees; self.onEditRemoteProject = onEditRemoteProject; self.onCloseWindow = onCloseWindow; self.onToggleCollapse = onToggleCollapse; self.onAddProject = onAddProject; self.onRequestPaneOutput = onRequestPaneOutput; self.onSendKeys = onSendKeys; self.onUpdateProject = onUpdateProject; self.onReorderProjects = onReorderProjects; self.pullRequests = pullRequests; self.shortcutHintsVisible = shortcutHintsVisible; self.isSidebarCollapsed = isSidebarCollapsed
    }

    public var body: some View {
        Group { isSidebarCollapsed ? AnyView(collapsedBody) : AnyView(expandedBody) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .alert("Rename Project", isPresented: Binding(get: { renamingProjectId != nil }, set: { if !$0 { renamingProjectId = nil } })) {
                TextField("Project name", text: $renameText)
                Button("Rename") { renameProject() }
                Button("Cancel", role: .cancel) { renamingProjectId = nil }
            }
    }

    private var expandedBody: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sortedProjects) { projectSection($0) }
                }
                .padding(.top, MoriTokens.Spacing.sm)
                .padding(.horizontal, MoriTokens.Spacing.sm)
                .padding(.bottom, MoriTokens.Spacing.sm)
            }
            sidebarFooter
        }
    }

    private var collapsedBody: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: MoriTokens.Spacing.lg) {
                ForEach(sortedProjects) { railProject($0) }
            }
            .padding(.vertical, MoriTokens.Spacing.lg)
        }
    }

    // MARK: - Project section

    private func projectSection(_ project: Project) -> some View {
        let isSelectedProject = project.id == selectedProjectId
        return VStack(alignment: .leading, spacing: 0) {
            projectHeader(project, selected: isSelectedProject)
            if !project.isCollapsed {
                worktreesGroup(project)
                    .padding(.bottom, MoriTokens.Spacing.md)
            }
        }
        .padding(.horizontal, MoriTokens.Spacing.xs)
        .overlay(alignment: .top) { if dropTargetProjectId == project.id && draggingProjectId != project.id { Rectangle().fill(MoriTokens.Color.active).frame(height: 2).padding(.horizontal, MoriTokens.Spacing.lg) } }
        .draggable(project.id.uuidString) { Text(project.name).padding().background(.regularMaterial) }
        .dropDestination(for: String.self) { items, _ in reorder(dragged: items.first, before: project) } isTargeted: { dropTargetProjectId = $0 ? project.id : nil }
        .onHover { hoveredProjectId = $0 ? project.id : nil }
        .contextMenu { projectActions(project) }
    }

    /// Folder + name. Tap toggles the project open/closed. Hover reveals the new
    /// workspace and overflow actions; an aggregate dot flags attention.
    private func projectHeader(_ project: Project, selected: Bool) -> some View {
        let agg = aggregateState(for: project)
        let isHovered = hoveredProjectId == project.id
        return HStack(spacing: MoriTokens.Spacing.md) {
            Image(systemName: "folder")
                .font(.system(size: 13))
                .foregroundStyle(selected ? Color.primary.opacity(0.9) : MoriTokens.Color.muted)
                .frame(width: 16)
            Text(project.name)
                .font(.system(size: 14, weight: selected ? .bold : .semibold))
                .foregroundStyle(selected ? Color.primary : Color.primary.opacity(0.7))
                .lineLimit(1)
            if project.isFavorite { Image(systemName: "pin.fill").font(.system(size: 9, weight: .semibold)).foregroundStyle(MoriTokens.Color.inactive) }
            Spacer(minLength: 0)
            if !isHovered, agg == .waiting || agg == .error {
                Circle().fill(agg == .error ? MoriTokens.Color.error : MoriTokens.Color.attention).frame(width: 7, height: 7)
            }
            if isHovered, onShowCreatePanel != nil {
                Button { onSelectProject?(project.id); onShowCreatePanel?() } label: { Image(systemName: "plus").font(MoriTokens.Font.sidebarAccessory).foregroundStyle(MoriTokens.Color.muted) }.buttonStyle(.plain).frame(width: MoriTokens.Size.sidebarAccessory).help("New Workspace…")
            }
            if isHovered {
                Menu { projectActions(project) } label: { Image(systemName: "ellipsis").font(MoriTokens.Font.sidebarAccessory).foregroundStyle(MoriTokens.Color.muted) }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: MoriTokens.Size.sidebarAccessory)
            }
        }
        .padding(.horizontal, MoriTokens.Spacing.sm)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { onToggleCollapse?(project.id); onSelectProject?(project.id) }
    }

    @ViewBuilder
    private func worktreesGroup(_ project: Project) -> some View {
        let all = visibleWorktrees(for: project)
        let showingAll = expandedProjects.contains(project.id)
        let visible = showingAll ? all : Array(all.prefix(worktreeLimit))
        VStack(alignment: .leading, spacing: 1) {
            if all.isEmpty {
                Text("No worktrees").font(MoriTokens.Font.caption).foregroundStyle(MoriTokens.Color.muted)
                    .padding(.horizontal, MoriTokens.Spacing.sm).padding(.vertical, MoriTokens.Spacing.xs)
            }
            ForEach(visible) { worktree in
                worktreeRow(worktree)
                if expandedWorktrees.contains(worktree.id) {
                    ForEach(allWindows(for: worktree)) { window in
                        WindowRowView(window: window, isActive: window.tmuxWindowId == selectedWindowId, shortcutIndex: globalWindowIndices[window.tmuxWindowId], shortcutHintsVisible: shortcutHintsVisible, onSelect: { onSelectWindow(window.tmuxWindowId) }, onRequestPaneOutput: onRequestPaneOutput, onSendKeys: onSendKeys)
                            .padding(.leading, MoriTokens.Spacing.xxl)
                            .padding(.horizontal, MoriTokens.Spacing.sm)
                    }
                }
            }
            if all.count > visible.count {
                showMoreButton(remaining: all.count - visible.count, project: project)
            }
        }
        .padding(.leading, MoriTokens.Spacing.lg)
    }

    private func showMoreButton(remaining: Int, project: Project) -> some View {
        Button { toggle(&expandedProjects, project.id) } label: {
            Text(String(format: String.localized("Show %lld more"), remaining))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(MoriTokens.Color.muted)
                .padding(.horizontal, MoriTokens.Spacing.sm)
                .padding(.vertical, MoriTokens.Spacing.xs)
        }.buttonStyle(.plain)
    }

    /// Compact single-line worktree row: branch glyph + name + (window chip) +
    /// relative time. Deliberately quiet — no git-diff strip or PR badge — so the
    /// list scans like the reference: tight, flat, one line per worktree.
    private func worktreeRow(_ worktree: Worktree) -> some View {
        let selected = worktree.id == selectedWorktreeId
        let wins = allWindows(for: worktree)
        let expanded = expandedWorktrees.contains(worktree.id)
        return Button { onSelectWorktree(worktree.id) } label: {
            HStack(spacing: MoriTokens.Spacing.md) {
                Image(systemName: worktreeGlyph(worktree))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(worktreeIconColor(worktree, selected: selected))
                    .frame(width: 15)
                Text(worktree.branch ?? worktree.name)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(worktreeNameColor(worktree, selected: selected))
                    .lineLimit(1)
                Spacer(minLength: MoriTokens.Spacing.sm)
                if wins.count >= 2 {
                    windowChip(count: wins.count, expanded: expanded, selected: selected, alert: hiddenWindowAlert(wins, expanded: expanded)) { toggle(&expandedWorktrees, worktree.id) }
                }
                if let time = relativeTime(worktree.lastActiveAt) {
                    Text(time)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(selected ? Color.primary.opacity(0.55) : MoriTokens.Color.inactive)
                }
            }
            .padding(.horizontal, MoriTokens.Spacing.sm)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(selected ? MoriTokens.Color.muted.opacity(0.22) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: MoriTokens.Radius.small))
        .contextMenu { WorktreeContextActions(worktree: worktree, pullRequest: pullRequests[worktree.id], onRemove: onRemoveWorktree.map { remove in { remove(worktree.id) } }) }
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
        if s < 60 { return String.localized("now") }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h" }
        if s < 604_800 { return "\(s / 86400)d" }
        return nil
    }

    // MARK: - Footer

    @ViewBuilder
    private var sidebarFooter: some View {
        if let onAddProject {
            HStack(spacing: MoriTokens.Spacing.md) {
                Button(action: onAddProject) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).foregroundStyle(MoriTokens.Color.muted)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).help(String.localized("Add Project"))
                Spacer()
            }
            .padding(.horizontal, MoriTokens.Spacing.md)
            .padding(.vertical, MoriTokens.Spacing.sm)
            .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(MoriTokens.Opacity.subtle)).frame(height: 1) }
        }
    }

    // MARK: - Collapsed rail

    private func railProject(_ project: Project) -> some View {
        let state = aggregateState(for: project)
        let selected = project.id == selectedProjectId || worktrees.contains { $0.projectId == project.id && $0.id == selectedWorktreeId }
        let waiting = visibleWorktrees(for: project).filter { $0.agentState == .waitingForInput }.count
        return Button { onSelectProject?(project.id) } label: {
            ProjectLetterTile(project: project, size: 34, cornerRadius: 9, fontSize: 13)
                .overlay {
                    if state == .waiting && !selected {
                        PulsingRing(color: state.color, cornerRadius: 9)
                    } else {
                        RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? MoriTokens.Color.active : state.color, lineWidth: (selected || state != .idle) ? 2 : 0)
                    }
                }
                .overlay(alignment: .topTrailing) { if waiting > 0 { Text("\(waiting)").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.black).padding(.horizontal, 4).frame(minWidth: 15, minHeight: 15).background(Capsule().fill(MoriTokens.Color.attention)).offset(x: 6, y: -5) } }
        }
        .buttonStyle(.plain)
        .help(project.name + "\n" + visibleWorktrees(for: project).map { "• \($0.name)" }.joined(separator: "\n"))
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

    private var sortedProjects: [Project] { projects.filter(\.isFavorite) + projects.filter { !$0.isFavorite } }
    private func visibleWorktrees(for project: Project) -> [Worktree] { worktrees.filter { $0.projectId == project.id && $0.status != .unavailable } }
    private func aggregateState(for project: Project) -> SidebarStatus { let ws = visibleWorktrees(for: project); if ws.contains(where: { $0.agentState == .error }) { return .error }; if ws.contains(where: { $0.agentState == .waitingForInput }) { return .waiting }; if ws.contains(where: { $0.agentState == .running }) { return .running }; return .idle }
    private func allWindows(for worktree: Worktree) -> [RuntimeWindow] { windows.filter { $0.worktreeId == worktree.id }.sorted { $0.tmuxWindowIndex < $1.tmuxWindowIndex } }
    private var globalWindowIndices: [String: Int] { var result: [String: Int] = [:]; var i = 1; for project in sortedProjects where !project.isCollapsed { for worktree in visibleWorktrees(for: project) { for window in allWindows(for: worktree) { if i <= 9 { result[window.tmuxWindowId] = i }; i += 1 } } }; return result }
    private func renameProject() { if let id = renamingProjectId, var project = projects.first(where: { $0.id == id }), !renameText.trimmingCharacters(in: .whitespaces).isEmpty { project.name = renameText.trimmingCharacters(in: .whitespaces); onUpdateProject?(project) }; renamingProjectId = nil }
    private func reorder(dragged: String?, before project: Project) -> Bool { guard let s = dragged, let draggedId = UUID(uuidString: s), draggedId != project.id else { dropTargetProjectId = nil; return false }; if var draggedProject = projects.first(where: { $0.id == draggedId }), draggedProject.isFavorite != project.isFavorite { draggedProject.isFavorite = project.isFavorite; onUpdateProject?(draggedProject) }; var ids = projects.map(\.id); guard let from = ids.firstIndex(of: draggedId), let to = ids.firstIndex(of: project.id) else { return false }; ids.remove(at: from); ids.insert(draggedId, at: to); onReorderProjects?(ids); dropTargetProjectId = nil; draggingProjectId = nil; return true }

    @ViewBuilder private func projectActions(_ project: Project) -> some View {
        if !project.isCollapsed, onShowCreatePanel != nil { Button { onSelectProject?(project.id); onShowCreatePanel?() } label: { Label("New Workspace…", systemImage: "plus") } }
        let editors = EditorLauncher.installed; if !editors.isEmpty { Divider(); ForEach(editors) { editor in Button { editor.open(path: project.repoRootPath) } label: { Label("Open in \(editor.name)", systemImage: editor.icon) } } }
        Divider(); Button { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.repoRootPath) } label: { Label("Reveal in Finder", systemImage: "folder") }
        Divider(); Button { renameText = project.name; renamingProjectId = project.id } label: { Label("Rename Project…", systemImage: "pencil") }
        Button { var updated = project; updated.isFavorite.toggle(); onUpdateProject?(updated) } label: { Label(project.isFavorite ? String.localized("Unpin Project") : String.localized("Pin Project"), systemImage: project.isFavorite ? "pin.slash" : "pin.fill") }
        if let onImportWorktrees, project.gitCommonDir != project.repoRootPath { Button { onImportWorktrees(project.id) } label: { Label("Import Existing Worktrees", systemImage: "square.and.arrow.down") } }
        if case .ssh = (project.location ?? .local), let onEditRemoteProject { Button { onEditRemoteProject(project.id) } label: { Label("Update Remote Credentials…", systemImage: "key") } }
        if let onRemoveProject { Divider(); Button(role: .destructive) { onRemoveProject(project.id) } label: { Label("Remove Project…", systemImage: "trash") } }
    }
}

private enum SidebarStatus { case waiting, running, idle, error; var color: Color { switch self { case .waiting: MoriTokens.Color.attention; case .running: MoriTokens.Color.success; case .idle: MoriTokens.Color.inactive.opacity(0.5); case .error: MoriTokens.Color.error } } }

/// A rounded-rect stroke that breathes — used on the collapsed rail to flag a
/// project whose agent is waiting on you.
private struct PulsingRing: View {
    let color: Color
    let cornerRadius: CGFloat
    @State private var dim = false
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .strokeBorder(color, lineWidth: 2)
            .opacity(dim ? 0.3 : 1)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: dim)
            .onAppear { dim = true }
    }
}
