import SwiftUI
import MoriCore

/// Sidebar redesigned as an attention inbox: agents needing input first, projects second.
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
    private let onEditRemoteProject: ((UUID) -> Void)?
    private let onCloseWindow: ((String) -> Void)?
    private let onToggleCollapse: ((UUID) -> Void)?
    private let onAddProject: (() -> Void)?
    private let onRequestPaneOutput: ((String, @escaping (String?) -> Void) -> Void)?
    private let onSendKeys: ((String, String) -> Void)?
    private let onUpdateProject: ((Project) -> Void)?
    private let onReorderProjects: (([UUID]) -> Void)?
    private let shortcutHintsVisible: Bool
    private let isSidebarCollapsed: Bool

    @State private var hoveredProjectId: UUID?
    @State private var renamingProjectId: UUID?
    @State private var renameText = ""
    @State private var draggingProjectId: UUID?
    @State private var dropTargetProjectId: UUID?
    @State private var filter: SidebarFilter = .all
    @State private var idleExpanded = false
    @State private var awakenedProjectIds: Set<UUID> = []

    public init(
        projects: [Project] = [], selectedProjectId: UUID? = nil, worktrees: [Worktree], windows: [RuntimeWindow], panes: [RuntimePane] = [], selectedWorktreeId: UUID?, selectedWindowId: String?, shortcutHintsVisible: Bool = false, onSelectProject: ((UUID) -> Void)? = nil, onSelectWorktree: @escaping (UUID) -> Void, onSelectWindow: @escaping (String) -> Void, onSelectPane: ((String) -> Void)? = nil, onShowCreatePanel: (() -> Void)? = nil, onRemoveWorktree: ((UUID) -> Void)? = nil, onRemoveProject: ((UUID) -> Void)? = nil, onEditRemoteProject: ((UUID) -> Void)? = nil, onCloseWindow: ((String) -> Void)? = nil, onToggleCollapse: ((UUID) -> Void)? = nil, onAddProject: (() -> Void)? = nil, onRequestPaneOutput: ((String, @escaping (String?) -> Void) -> Void)? = nil, onSendKeys: ((String, String) -> Void)? = nil, onUpdateProject: ((Project) -> Void)? = nil, onReorderProjects: (([UUID]) -> Void)? = nil, isSidebarCollapsed: Bool = false
    ) {
        self.projects = projects; self.selectedProjectId = selectedProjectId; self.worktrees = worktrees; self.windows = windows; self.panes = panes; self.selectedWorktreeId = selectedWorktreeId; self.selectedWindowId = selectedWindowId; self.onSelectProject = onSelectProject; self.onSelectWorktree = onSelectWorktree; self.onSelectWindow = onSelectWindow; self.onSelectPane = onSelectPane; self.onShowCreatePanel = onShowCreatePanel; self.onRemoveWorktree = onRemoveWorktree; self.onRemoveProject = onRemoveProject; self.onEditRemoteProject = onEditRemoteProject; self.onCloseWindow = onCloseWindow; self.onToggleCollapse = onToggleCollapse; self.onAddProject = onAddProject; self.onRequestPaneOutput = onRequestPaneOutput; self.onSendKeys = onSendKeys; self.onUpdateProject = onUpdateProject; self.onReorderProjects = onReorderProjects; self.shortcutHintsVisible = shortcutHintsVisible; self.isSidebarCollapsed = isSidebarCollapsed
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
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: MoriTokens.Spacing.sm) {
                filterBar
                if filter != .running { needsYouSection }
                if filter != .waiting { runningSection }
                projectsHeader
                ForEach(mainProjects) { projectSection($0) }
                if filter == .all { idleCluster }
            }
            .padding(.top, MoriTokens.Spacing.lg)
            .padding(.horizontal, MoriTokens.Spacing.sm)
            .padding(.bottom, MoriTokens.Spacing.sm)
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

    private var filterBar: some View {
        HStack(spacing: MoriTokens.Spacing.sm) {
            filterPill(.all, label: String.localized("All"), count: availableWorktreeCount)
            filterPill(.waiting, label: "●", count: waitingItems.count, tint: MoriTokens.Color.attention)
            filterPill(.running, label: "●", count: runningItems.count, tint: MoriTokens.Color.success)
            Spacer()
        }
        .padding(.horizontal, MoriTokens.Spacing.md)
        .padding(.bottom, MoriTokens.Spacing.sm)
    }

    private func filterPill(_ value: SidebarFilter, label: String, count: Int, tint: Color = .primary) -> some View {
        Button { filter = value } label: {
            HStack(spacing: MoriTokens.Spacing.sm) {
                Text(label).foregroundStyle(tint)
                Text("\(count)").font(MoriTokens.Font.monoSmall)
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(filter == value ? Color.primary : MoriTokens.Color.muted)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(filter == value ? MoriTokens.Color.muted.opacity(MoriTokens.Opacity.subtle) : Color.clear))
            .overlay(Capsule().strokeBorder(filter == value ? Color.primary.opacity(MoriTokens.Opacity.subtle) : Color.clear))
        }.buttonStyle(.plain)
    }

    @ViewBuilder private var needsYouSection: some View {
        if !waitingItems.isEmpty {
            sectionTitle(String.localized("Needs You"), color: MoriTokens.Color.attention, count: waitingItems.count)
            ForEach(Array(waitingItems.enumerated()), id: \.element.id) { offset, item in
                NeedsYouCard(item: item, shortcutIndex: shortcutHintsVisible ? offset + 1 : nil, onSelect: { select(item) }, onRequestPaneOutput: onRequestPaneOutput, onSendKeys: onSendKeys)
            }
        }
    }

    @ViewBuilder private var runningSection: some View {
        if !runningItems.isEmpty {
            sectionTitle(String.localized("Running"), color: MoriTokens.Color.success, count: runningItems.count)
            ForEach(Array(runningItems.enumerated()), id: \.element.id) { offset, item in
                AgentCompactRow(item: item, shortcutIndex: shortcutHintsVisible ? waitingItems.count + offset + 1 : nil) { select(item) }
            }
        }
    }

    private var projectsHeader: some View {
        sectionHeader { Text(String.localized("Projects")).font(MoriTokens.Font.sectionTitle).tracking(MoriTokens.Sidebar.sectionTracking).foregroundStyle(MoriTokens.Color.muted) } accessory: {
            if let onAddProject { Button(action: onAddProject) { Image(systemName: "plus").font(.system(size: 12, weight: .medium)).foregroundStyle(MoriTokens.Color.muted) }.buttonStyle(.plain).help(String.localized("Add Project")) }
        }.padding(.top, MoriTokens.Spacing.lg)
    }

    private func projectSection(_ project: Project) -> some View {
        let projectWorktrees = visibleWorktrees(for: project)
        let isSelectedProject = project.id == selectedProjectId
        return VStack(alignment: .leading, spacing: 0) {
            projectHeader(project, count: projectWorktrees.count, selected: isSelectedProject)
            if !project.isCollapsed {
                VStack(alignment: .leading, spacing: MoriTokens.Spacing.xs) {
                    if projectWorktrees.isEmpty, project.id == selectedProjectId { Text("No worktrees").font(MoriTokens.Font.caption).foregroundStyle(MoriTokens.Color.muted).padding(.horizontal, MoriTokens.Spacing.xl).padding(.vertical, MoriTokens.Spacing.sm) }
                    ForEach(projectWorktrees) { worktree in
                        worktreeRow(worktree)
                        ForEach(visibleDetailWindows(for: worktree)) { window in
                            WindowRowView(window: window, isActive: window.tmuxWindowId == selectedWindowId, shortcutIndex: globalWindowIndices[window.tmuxWindowId], shortcutHintsVisible: shortcutHintsVisible, onSelect: { onSelectWindow(window.tmuxWindowId) }, onRequestPaneOutput: onRequestPaneOutput, onSendKeys: onSendKeys)
                                .padding(.leading, MoriTokens.Spacing.xxl)
                                .padding(.horizontal, MoriTokens.Spacing.sm)
                        }
                    }
                }.padding(.top, MoriTokens.Spacing.xs).padding(.bottom, MoriTokens.Spacing.xs)
            }
        }
        .opacity(projectMatchesFilter(project) ? 1 : 0.32)
        .padding(.horizontal, MoriTokens.Spacing.xs)
        .overlay(alignment: .top) { if dropTargetProjectId == project.id && draggingProjectId != project.id { Rectangle().fill(MoriTokens.Color.active).frame(height: 2).padding(.horizontal, MoriTokens.Spacing.lg) } }
        .draggable(project.id.uuidString) { Text(project.name).padding().background(.regularMaterial) }
        .dropDestination(for: String.self) { items, _ in reorder(dragged: items.first, before: project) } isTargeted: { dropTargetProjectId = $0 ? project.id : nil }
        .onHover { hoveredProjectId = $0 ? project.id : nil }
        .contextMenu { projectActions(project) }
    }

    private func projectHeader(_ project: Project, count: Int, selected: Bool) -> some View {
        HStack(spacing: MoriTokens.Spacing.md) {
            Image(systemName: project.isCollapsed ? "chevron.right" : "chevron.down").font(MoriTokens.Font.sidebarChevron).foregroundStyle(MoriTokens.Color.inactive).frame(width: MoriTokens.Size.sidebarChevron)
            ProjectLetterTile(project: project)
            Text(project.name).font(MoriTokens.Font.projectTitle).foregroundStyle(Color.primary).lineLimit(1)
            if project.isFavorite { Image(systemName: "pin.fill").font(.system(size: 9, weight: .semibold)).foregroundStyle(MoriTokens.Color.inactive) }
            Spacer(minLength: 0)
            StatusDot(state: aggregateState(for: project), pulsing: aggregateState(for: project) == .waiting)
            if hoveredProjectId == project.id { Menu { projectActions(project) } label: { Image(systemName: "ellipsis").font(MoriTokens.Font.sidebarAccessory).foregroundStyle(MoriTokens.Color.muted) }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: MoriTokens.Size.sidebarAccessory) }
        }
        .padding(.horizontal, MoriTokens.Spacing.md)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: MoriTokens.Radius.small).fill(selected ? MoriTokens.Color.active.opacity(MoriTokens.Opacity.quiet) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { onToggleCollapse?(project.id); onSelectProject?(project.id) }
    }

    private func worktreeRow(_ worktree: Worktree) -> some View {
        WorktreeRowView(worktree: worktree, agentName: nil, isSelected: worktree.id == selectedWorktreeId, onSelect: { onSelectWorktree(worktree.id) }, onRemove: onRemoveWorktree.map { remove in { remove(worktree.id) } })
            .padding(.leading, 14)
            .padding(.horizontal, MoriTokens.Spacing.sm)
            .overlay(alignment: .leading) { Rectangle().fill(Color.primary.opacity(MoriTokens.Opacity.subtle)).frame(width: 1).padding(.leading, 18) }
            .contextMenu { worktreeActions(worktree) }
    }

    @ViewBuilder private var idleCluster: some View {
        if !idleProjects.isEmpty {
            Button { idleExpanded.toggle() } label: { HStack(spacing: MoriTokens.Spacing.md) { Image(systemName: idleExpanded ? "chevron.down" : "chevron.right").font(MoriTokens.Font.sidebarChevron); Text(String(format: String.localized("%lld idle projects"), idleProjects.count)).font(.system(size: 12, weight: .medium)); Spacer() }.foregroundStyle(MoriTokens.Color.inactive).padding(.horizontal, MoriTokens.Spacing.md).padding(.vertical, MoriTokens.Spacing.md).overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(MoriTokens.Opacity.subtle)).frame(height: 1) } }.buttonStyle(.plain)
            if idleExpanded { FlowLayout(items: idleProjects) { project in Button { awakenedProjectIds.insert(project.id); onSelectProject?(project.id); if let worktree = visibleWorktrees(for: project).first { onSelectWorktree(worktree.id) } } label: { HStack(spacing: MoriTokens.Spacing.sm) { ProjectLetterTile(project: project).scaleEffect(0.84); Text(project.name).font(.system(size: 12, weight: .medium)).lineLimit(1) }.padding(.horizontal, MoriTokens.Spacing.sm).padding(.vertical, MoriTokens.Spacing.xs).overlay(RoundedRectangle(cornerRadius: MoriTokens.Radius.small).strokeBorder(Color.primary.opacity(MoriTokens.Opacity.subtle))) }.buttonStyle(.plain) }.padding(.horizontal, MoriTokens.Spacing.md) }
        }
    }

    private func railProject(_ project: Project) -> some View {
        let state = aggregateState(for: project)
        let selected = project.id == selectedProjectId || worktrees.contains { $0.projectId == project.id && $0.id == selectedWorktreeId }
        let waiting = visibleWorktrees(for: project).filter { $0.agentState == .waitingForInput }.count
        return Button { onSelectProject?(project.id) } label: {
            ProjectLetterTile(project: project, size: 34, cornerRadius: 9, fontSize: 13)
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? MoriTokens.Color.active : state.color, lineWidth: (selected || state != .idle) ? 2 : 0))
                .overlay(alignment: .topTrailing) { if waiting > 0 { Text("\(waiting)").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.black).padding(.horizontal, 4).frame(minWidth: 15, minHeight: 15).background(Capsule().fill(MoriTokens.Color.attention)).offset(x: 6, y: -5) } }
        }
        .buttonStyle(.plain)
        .help(project.name + "\n" + visibleWorktrees(for: project).map { "• \($0.name)" }.joined(separator: "\n"))
    }

    private func sectionTitle(_ title: String, color: Color, count: Int) -> some View { sectionHeader { HStack(spacing: MoriTokens.Spacing.sm) { StatusDot(state: color == MoriTokens.Color.attention ? .waiting : .running, pulsing: color == MoriTokens.Color.attention); Text(title).font(MoriTokens.Font.sectionTitle).tracking(MoriTokens.Sidebar.sectionTracking).foregroundStyle(color) } } accessory: { Text("\(count)").font(MoriTokens.Font.caption).foregroundStyle(MoriTokens.Color.inactive) } }
    private func sectionHeader<Title: View, Accessory: View>(@ViewBuilder title: () -> Title, @ViewBuilder accessory: () -> Accessory) -> some View { HStack { title(); Spacer(); accessory() }.padding(.horizontal, MoriTokens.Spacing.xl).padding(.bottom, MoriTokens.Spacing.sm) }

    private var sortedProjects: [Project] { projects.filter(\.isFavorite) + projects.filter { !$0.isFavorite } }
    private var projectNamesById: [UUID: String] { Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) }) }
    private var availableWorktreeCount: Int { worktrees.filter { $0.status != .unavailable }.count }
    private var agentItems: [AgentPaneItem] { panes.filter { $0.detectedAgent != nil || $0.agentState != .none }.compactMap { pane in guard let window = windows.first(where: { $0.tmuxWindowId == pane.tmuxWindowId }), let worktree = worktrees.first(where: { $0.id == window.worktreeId }), worktree.status != .unavailable, let projectName = projectNamesById[worktree.projectId] else { return nil }; return AgentPaneItem(pane: pane, window: window, worktree: worktree, projectName: projectName) } }
    private var waitingItems: [AgentPaneItem] { agentItems.filter { $0.pane.agentState == .waitingForInput } }
    private var runningItems: [AgentPaneItem] { agentItems.filter { $0.pane.agentState == .running } }
    private var idleProjects: [Project] { sortedProjects.filter { !($0.isFavorite || awakenedProjectIds.contains($0.id) || $0.id == selectedProjectId) && visibleWorktrees(for: $0).allSatisfy { worktree in worktree.agentState == .none && worktree.status != .active && !allWindows(for: worktree).contains(where: \.hasUnreadOutput) } } }
    private var mainProjects: [Project] { sortedProjects.filter { !idleProjects.map(\.id).contains($0.id) } }
    private func visibleWorktrees(for project: Project) -> [Worktree] { worktrees.filter { $0.projectId == project.id && $0.status != .unavailable } }
    private func projectMatchesFilter(_ project: Project) -> Bool { filter == .all || visibleWorktrees(for: project).contains { filter == .waiting ? $0.agentState == .waitingForInput : ($0.agentState == .running || $0.status == .active) } }
    private func aggregateState(for project: Project) -> SidebarStatus { let ws = visibleWorktrees(for: project); if ws.contains(where: { $0.agentState == .error }) { return .error }; if ws.contains(where: { $0.agentState == .waitingForInput }) { return .waiting }; if ws.contains(where: { $0.agentState == .running }) { return .running }; return .idle }
    private func allWindows(for worktree: Worktree) -> [RuntimeWindow] { windows.filter { $0.worktreeId == worktree.id }.sorted { $0.tmuxWindowIndex < $1.tmuxWindowIndex } }
    private func visibleDetailWindows(for worktree: Worktree) -> [RuntimeWindow] { let all = allWindows(for: worktree); let relevant = all.filter { $0.tmuxWindowId == selectedWindowId || $0.detectedAgent != nil || $0.agentState != .none || $0.badge != nil || $0.hasUnreadOutput }; return relevant.isEmpty ? Array(all.prefix(1)) : relevant }
    private var globalWindowIndices: [String: Int] { var result: [String: Int] = [:]; var i = waitingItems.count + runningItems.count + 1; for project in sortedProjects where !project.isCollapsed { for worktree in visibleWorktrees(for: project) { for window in allWindows(for: worktree) { if i <= 9 { result[window.tmuxWindowId] = i }; i += 1 } } }; return result }
    private func select(_ item: AgentPaneItem) { onSelectProject?(item.worktree.projectId); onSelectWorktree(item.worktree.id); if let onSelectPane { onSelectPane(item.pane.tmuxPaneId) } else { onSelectWindow(item.window.tmuxWindowId) } }
    private func renameProject() { if let id = renamingProjectId, var project = projects.first(where: { $0.id == id }), !renameText.trimmingCharacters(in: .whitespaces).isEmpty { project.name = renameText.trimmingCharacters(in: .whitespaces); onUpdateProject?(project) }; renamingProjectId = nil }
    private func reorder(dragged: String?, before project: Project) -> Bool { guard let s = dragged, let draggedId = UUID(uuidString: s), draggedId != project.id else { dropTargetProjectId = nil; return false }; if var draggedProject = projects.first(where: { $0.id == draggedId }), draggedProject.isFavorite != project.isFavorite { draggedProject.isFavorite = project.isFavorite; onUpdateProject?(draggedProject) }; var ids = projects.map(\.id); guard let from = ids.firstIndex(of: draggedId), let to = ids.firstIndex(of: project.id) else { return false }; ids.remove(at: from); ids.insert(draggedId, at: to); onReorderProjects?(ids); dropTargetProjectId = nil; draggingProjectId = nil; return true }

    @ViewBuilder private func projectActions(_ project: Project) -> some View {
        if !project.isCollapsed, onShowCreatePanel != nil { Button { onSelectProject?(project.id); onShowCreatePanel?() } label: { Label("New Workspace…", systemImage: "plus") } }
        let editors = EditorLauncher.installed; if !editors.isEmpty { Divider(); ForEach(editors) { editor in Button { editor.open(path: project.repoRootPath) } label: { Label("Open in \(editor.name)", systemImage: editor.icon) } } }
        Divider(); Button { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.repoRootPath) } label: { Label("Reveal in Finder", systemImage: "folder") }
        Divider(); Button { renameText = project.name; renamingProjectId = project.id } label: { Label("Rename Project…", systemImage: "pencil") }
        Button { var updated = project; updated.isFavorite.toggle(); onUpdateProject?(updated) } label: { Label(project.isFavorite ? String.localized("Unpin Project") : String.localized("Pin Project"), systemImage: project.isFavorite ? "pin.slash" : "pin.fill") }
        if case .ssh = (project.location ?? .local), let onEditRemoteProject { Button { onEditRemoteProject(project.id) } label: { Label("Update Remote Credentials…", systemImage: "key") } }
        if let onRemoveProject { Divider(); Button(role: .destructive) { onRemoveProject(project.id) } label: { Label("Remove Project…", systemImage: "trash") } }
    }
    @ViewBuilder private func worktreeActions(_ worktree: Worktree) -> some View { let editors = EditorLauncher.installed; if !editors.isEmpty { ForEach(editors) { editor in Button { editor.open(path: worktree.path) } label: { Label("Open in \(editor.name)", systemImage: editor.icon) } }; Divider() }; Button { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: worktree.path) } label: { Label("Reveal in Finder", systemImage: "folder") }; if !worktree.isMainWorktree, let onRemoveWorktree { Divider(); Button(role: .destructive) { onRemoveWorktree(worktree.id) } label: { Label("Remove Worktree…", systemImage: "trash") } } }
}

private enum SidebarFilter { case all, waiting, running }
private enum SidebarStatus { case waiting, running, idle, error; var color: Color { switch self { case .waiting: MoriTokens.Color.attention; case .running: MoriTokens.Color.success; case .idle: MoriTokens.Color.inactive.opacity(0.5); case .error: MoriTokens.Color.error } } }
private struct AgentPaneItem: Identifiable { let pane: RuntimePane; let window: RuntimeWindow; let worktree: Worktree; let projectName: String; var id: String { pane.tmuxPaneId }; var agentName: String { pane.detectedAgent ?? window.detectedAgent ?? window.title }; var path: String { "\(projectName)/\(worktree.branch ?? worktree.name)" }; var elapsed: String { RelativeTime.short(since: worktree.lastActiveAt) } }

private struct StatusDot: View { let state: SidebarStatus; var pulsing = false; var body: some View { Circle().fill(state == .idle ? Color.clear : state.color).frame(width: MoriTokens.Icon.dot, height: MoriTokens.Icon.dot).overlay(Circle().strokeBorder(state == .idle ? state.color : Color.clear, lineWidth: 1.5)).symbolEffect(.pulse, options: .repeating, value: pulsing) } }
private struct AgentCompactRow: View { let item: AgentPaneItem; let shortcutIndex: Int?; let onSelect: () -> Void; var body: some View { Button(action: onSelect) { HStack(spacing: MoriTokens.Spacing.md) { ProgressView().controlSize(.small).tint(MoriTokens.Color.success); Text(item.agentName).font(.system(size: 12, weight: .semibold, design: .monospaced)); Text(item.path).font(MoriTokens.Font.monoSmall).foregroundStyle(MoriTokens.Color.muted).lineLimit(1); Spacer(); if let shortcutIndex { ShortcutHintPill("⌘\(shortcutIndex)") } else { Text(item.elapsed).font(MoriTokens.Font.monoSmall).foregroundStyle(MoriTokens.Color.inactive) } }.padding(.horizontal, MoriTokens.Spacing.lg).padding(.vertical, 7).contentShape(Rectangle()) }.buttonStyle(.plain) } }

private struct NeedsYouCard: View { let item: AgentPaneItem; let shortcutIndex: Int?; let onSelect: () -> Void; let onRequestPaneOutput: ((String, @escaping (String?) -> Void) -> Void)?; let onSendKeys: ((String, String) -> Void)?; @State private var output: String?; @State private var replying = false; @State private var sent = false
    var body: some View { VStack(alignment: .leading, spacing: MoriTokens.Spacing.sm) { Button(action: { replying = true; onSelect(); load() }) { HStack(spacing: MoriTokens.Spacing.md) { sent ? AnyView(ProgressView().controlSize(.small).tint(MoriTokens.Color.success)) : AnyView(StatusDot(state: .waiting, pulsing: true)); Text(item.agentName).font(.system(size: 12, weight: .semibold, design: .monospaced)); Text(item.path).font(MoriTokens.Font.monoSmall).foregroundStyle(MoriTokens.Color.muted).lineLimit(1); Spacer(); if let shortcutIndex { ShortcutHintPill("⌘\(shortcutIndex)") } else { Text(sent ? String.localized("sent") : item.elapsed).font(MoriTokens.Font.monoSmall).foregroundStyle(sent ? MoriTokens.Color.success : MoriTokens.Color.attention) } }.contentShape(Rectangle()) }.buttonStyle(.plain); Text(sent ? String.localized("reply sent — resuming…") : question).font(.system(size: 12)).foregroundStyle(sent ? MoriTokens.Color.success : MoriTokens.Color.muted).lineLimit(2).padding(.leading, MoriTokens.Spacing.md).overlay(alignment: .leading) { Rectangle().fill(MoriTokens.Color.attention.opacity(0.35)).frame(width: 2) }; if replying && !sent { QuickReplyField(onSend: { text in onSendKeys?(item.pane.tmuxPaneId, text + "\n"); sent = true; replying = false }, onDismiss: { replying = false }).padding(.leading, MoriTokens.Spacing.md) } }.padding(10).background(RoundedRectangle(cornerRadius: 9).fill(MoriTokens.Color.muted.opacity(MoriTokens.Opacity.subtle))).overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(MoriTokens.Color.attention.opacity(0.22))).onAppear(perform: load) }
    private var question: String { output?.split(separator: "\n").last.map(String.init) ?? String.localized("Waiting for input") }
    private func load() { guard output == nil else { return }; onRequestPaneOutput?(item.pane.tmuxPaneId) { output = $0 } }
}

private enum RelativeTime { static func short(since date: Date?) -> String { guard let date else { return "—" }; let seconds = max(0, Int(-date.timeIntervalSinceNow)); if seconds < 60 { return String.localized("now") }; if seconds < 3600 { return "\(seconds / 60)m" }; if seconds < 86400 { return "\(seconds / 3600)h" }; return "\(seconds / 86400)d" } }

private struct FlowLayout<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable { let items: Data; let content: (Data.Element) -> Content; var body: some View { LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: MoriTokens.Spacing.sm)], alignment: .leading, spacing: MoriTokens.Spacing.sm) { ForEach(items) { content($0) } } } }
