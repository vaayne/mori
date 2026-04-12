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
    private let onSetWorkflowStatus: ((UUID, WorkflowStatus) -> Void)?
    private let onRequestPaneOutput: ((String, @escaping (String?) -> Void) -> Void)?
    private let onSendKeys: ((String, String) -> Void)?
    private let onUpdateProject: ((Project) -> Void)?
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
        onSetWorkflowStatus: ((UUID, WorkflowStatus) -> Void)? = nil,
        onRequestPaneOutput: ((String, @escaping (String?) -> Void) -> Void)? = nil,
        onSendKeys: ((String, String) -> Void)? = nil,
        onUpdateProject: ((Project) -> Void)? = nil
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
        self.onSetWorkflowStatus = onSetWorkflowStatus
        self.onRequestPaneOutput = onRequestPaneOutput
        self.onSendKeys = onSendKeys
        self.onUpdateProject = onUpdateProject
        self.shortcutHintsVisible = shortcutHintsVisible
    }

    /// Count of agent windows needing attention across all worktrees.
    private var attentionCount: Int {
        windows.filter { $0.agentState == .waitingForInput || $0.agentState == .error }.count
    }

    /// Global 1-based index for each window across all projects and worktrees.
    /// Iterates projects in display order so indices match ⌘1-9 quick jump.
    private var globalWindowIndices: [String: Int] {
        var result: [String: Int] = [:]
        var globalIndex = 1
        for project in projects where !project.isCollapsed {
            let projectWorktrees = worktrees
                .filter { $0.projectId == project.id && $0.status != .unavailable }
            for worktree in projectWorktrees {
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
        }
        return result
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    attentionBanner

                    // "PROJECTS" section header
                    HStack {
                        Text(String.localized("PROJECTS"))
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(MoriTokens.Color.muted)

                        Spacer()

                        if let onAddProject {
                            Button(action: onAddProject) {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(MoriTokens.Color.muted)
                            }
                            .buttonStyle(.plain)
                            .help("Add Project")
                        }
                    }
                    .padding(.horizontal, MoriTokens.Spacing.xl)
                    .padding(.top, MoriTokens.Spacing.lg)
                    .padding(.bottom, MoriTokens.Spacing.sm)

                    ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                        if index > 0 {
                            Divider()
                                .padding(.horizontal, MoriTokens.Spacing.xl)
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

    @ViewBuilder
    private func projectSection(_ project: Project) -> some View {
        // Section header: chevron + name + hover-reveal + button
        HStack(spacing: MoriTokens.Spacing.md) {
            Image(systemName: project.isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MoriTokens.Color.muted)
                .frame(width: 12)

            Text(project.name)
                .font(MoriTokens.Font.projectTitle)
                .foregroundStyle(MoriTokens.Color.muted)

            Spacer()

            let projectWorktreeCount = worktrees.filter { $0.projectId == project.id && $0.status != .unavailable }.count
            Text("\(projectWorktreeCount)")
                .font(MoriTokens.Font.caption)
                .foregroundStyle(MoriTokens.Color.inactive)

            if hoveredProjectId == project.id {
                HStack(spacing: MoriTokens.Spacing.sm) {
                    if !project.isCollapsed, onShowCreatePanel != nil {
                        Button {
                            onSelectProject?(project.id)
                            onShowCreatePanel?()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(MoriTokens.Color.muted)
                        }
                        .buttonStyle(.plain)
                        .help("New Workspace")
                    }

                    Menu {
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
        .animation(.easeInOut(duration: 0.14), value: shortcutHintsVisible)
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
            if onShowCreatePanel != nil {
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
        let worktreeWindows = windows
            .filter { $0.worktreeId == worktree.id }
            .sorted { $0.tmuxWindowIndex < $1.tmuxWindowIndex }
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
                if let onSetWorkflowStatus {
                    WorkflowStatusMenu(
                        currentStatus: worktree.workflowStatus,
                        onSetStatus: { status in onSetWorkflowStatus(worktree.id, status) }
                    )
                    Divider()
                }

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

            // Show windows (tabs) under every worktree that has them — tree connector
            if !worktreeWindows.isEmpty {
                TreeConnectorGroup(data: worktreeWindows) { window in
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

    // MARK: - Attention Banner

    @ViewBuilder
    private var attentionBanner: some View {
        let count = attentionCount
        if count > 0 {
            HStack(spacing: MoriTokens.Spacing.md) {
                Image(systemName: "exclamationmark.bubble.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(MoriTokens.Color.attention)
                Text(count == 1
                    ? String.localized("1 agent needs attention")
                    : String.localized("\(count) agents need attention"))
                    .font(MoriTokens.Font.caption)
                    .foregroundStyle(MoriTokens.Color.attention)
                Spacer()
            }
            .padding(.horizontal, MoriTokens.Spacing.xl)
            .padding(.vertical, MoriTokens.Spacing.md)
            .background(MoriTokens.Color.attention.opacity(MoriTokens.Opacity.subtle))
            .clipShape(RoundedRectangle(cornerRadius: MoriTokens.Radius.small))
            .padding(.horizontal, MoriTokens.Spacing.sm)
            .padding(.bottom, MoriTokens.Spacing.sm)
        }
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
