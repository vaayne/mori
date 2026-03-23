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

    public init(
        projects: [Project] = [],
        selectedProjectId: UUID? = nil,
        worktrees: [Worktree],
        windows: [RuntimeWindow],
        selectedWorktreeId: UUID?,
        selectedWindowId: String?,
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
        onSetWorkflowStatus: ((UUID, WorkflowStatus) -> Void)? = nil
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
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
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
    }

    // MARK: - Project Section

    @State private var hoveredProjectId: UUID?

    @ViewBuilder
    private func projectSection(_ project: Project) -> some View {
        // Section header: chevron + name + hover-reveal + button
        HStack(spacing: MoriTokens.Spacing.md) {
            Image(systemName: project.isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MoriTokens.Color.muted)
                .frame(width: 12)

            Text(project.name)
                .font(MoriTokens.Font.sectionTitle)
                .foregroundStyle(MoriTokens.Color.muted)

            Spacer()

            if hoveredProjectId == project.id {
                HStack(spacing: MoriTokens.Spacing.sm) {
                    if !project.isCollapsed, onShowCreatePanel != nil {
                        Button {
                            onSelectProject?(project.id)
                            onShowCreatePanel?()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .medium))
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
        .padding(.top, MoriTokens.Spacing.xl)
        .padding(.bottom, MoriTokens.Spacing.sm)
        .contentShape(Rectangle())
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

        VStack(alignment: .leading, spacing: 0) {
            WorktreeRowView(
                worktree: worktree,
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

            // Show windows (tabs) under every worktree that has them
            if !worktreeWindows.isEmpty {
                ForEach(Array(worktreeWindows.enumerated()), id: \.element.id) { index, window in
                    WindowRowView(
                        window: window,
                        isActive: isSelected && window.tmuxWindowId == selectedWindowId,
                        shortcutIndex: isSelected && index < 9 ? index + 1 : nil,
                        onSelect: { onSelectWindow(window.tmuxWindowId) }
                    )
                    .padding(.leading, MoriTokens.Spacing.xxl)
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
