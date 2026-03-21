import SwiftUI
import MoriCore

/// Task mode sidebar: groups all worktrees across projects by WorkflowStatus.
/// Pure SwiftUI view — data + callbacks, no direct AppState dependency.
public struct TaskSidebarView: View {
    private let projects: [Project]
    private let worktrees: [Worktree]
    private let windows: [RuntimeWindow]
    private let selectedWorktreeId: UUID?
    private let selectedWindowId: String?
    private let onSelectWorktree: (UUID) -> Void
    private let onSelectWindow: (String) -> Void
    private let onCloseWindow: ((String) -> Void)?
    private let onSetWorkflowStatus: ((UUID, WorkflowStatus) -> Void)?
    private let onAddProject: (() -> Void)?
    private let onOpenSettings: (() -> Void)?
    private let onOpenCommandPalette: (() -> Void)?

    @State private var showCancelled = false
    @State private var collapsedGroups: Set<WorkflowStatus> = [.done]

    /// Status group display order (cancelled excluded — controlled by toggle).
    private static let visibleStatuses: [WorkflowStatus] = [.inProgress, .needsReview, .todo, .done]

    public init(
        projects: [Project] = [],
        worktrees: [Worktree],
        windows: [RuntimeWindow],
        selectedWorktreeId: UUID?,
        selectedWindowId: String?,
        onSelectWorktree: @escaping (UUID) -> Void,
        onSelectWindow: @escaping (String) -> Void,
        onCloseWindow: ((String) -> Void)? = nil,
        onSetWorkflowStatus: ((UUID, WorkflowStatus) -> Void)? = nil,
        onAddProject: (() -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onOpenCommandPalette: (() -> Void)? = nil
    ) {
        self.projects = projects
        self.worktrees = worktrees
        self.windows = windows
        self.selectedWorktreeId = selectedWorktreeId
        self.selectedWindowId = selectedWindowId
        self.onSelectWorktree = onSelectWorktree
        self.onSelectWindow = onSelectWindow
        self.onCloseWindow = onCloseWindow
        self.onSetWorkflowStatus = onSetWorkflowStatus
        self.onAddProject = onAddProject
        self.onOpenSettings = onOpenSettings
        self.onOpenCommandPalette = onOpenCommandPalette
    }

    /// Worktrees filtered to exclude unavailable, keyed by project ID for lookup.
    private var projectMap: [UUID: Project] {
        Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
    }

    private var availableWorktrees: [Worktree] {
        worktrees.filter { $0.status != .unavailable }
    }

    private func worktreesForStatus(_ status: WorkflowStatus) -> [Worktree] {
        availableWorktrees
            .filter { $0.workflowStatus == status }
            .sorted { ($0.lastActiveAt ?? .distantPast) > ($1.lastActiveAt ?? .distantPast) }
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Self.visibleStatuses, id: \.self) { status in
                        let items = worktreesForStatus(status)
                        if !items.isEmpty {
                            statusGroup(status: status, worktrees: items)
                        }
                    }

                    // Cancelled group (togglable)
                    if showCancelled {
                        let cancelledItems = worktreesForStatus(.cancelled)
                        if !cancelledItems.isEmpty {
                            statusGroup(status: .cancelled, worktrees: cancelledItems)
                        }
                    }

                    // Show cancelled toggle
                    let cancelledCount = worktreesForStatus(.cancelled).count
                    if cancelledCount > 0 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showCancelled.toggle()
                            }
                        } label: {
                            HStack(spacing: MoriTokens.Spacing.sm) {
                                Image(systemName: showCancelled ? "eye.slash" : "eye")
                                    .font(.system(size: 10))
                                Text(showCancelled ? "Hide Cancelled" : "Show Cancelled (\(cancelledCount))")
                                    .font(MoriTokens.Font.caption)
                            }
                            .foregroundStyle(MoriTokens.Color.muted)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, MoriTokens.Spacing.xl)
                        .padding(.vertical, MoriTokens.Spacing.lg)
                    }
                }
                .padding(.top, MoriTokens.Spacing.lg)
            }

            Spacer(minLength: 0)

            sidebarFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Status Group

    @ViewBuilder
    private func statusGroup(status: WorkflowStatus, worktrees: [Worktree]) -> some View {
        let isCollapsed = collapsedGroups.contains(status)

        // Group header
        HStack(spacing: MoriTokens.Spacing.md) {
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MoriTokens.Color.muted)
                .frame(width: 12)

            Image(systemName: status.iconName)
                .font(.system(size: 11))
                .foregroundStyle(MoriTokens.Color.muted)

            Text(status.displayName)
                .font(MoriTokens.Font.sectionTitle)
                .foregroundStyle(MoriTokens.Color.muted)

            Text("\(worktrees.count)")
                .font(MoriTokens.Font.caption)
                .foregroundStyle(MoriTokens.Color.inactive)

            Spacer()
        }
        .padding(.horizontal, MoriTokens.Spacing.xl)
        .padding(.top, MoriTokens.Spacing.xl)
        .padding(.bottom, MoriTokens.Spacing.sm)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                if collapsedGroups.contains(status) {
                    collapsedGroups.remove(status)
                } else {
                    collapsedGroups.insert(status)
                }
            }
        }

        if !isCollapsed {
            ForEach(worktrees) { worktree in
                taskWorktreeRow(worktree)
            }
        }
    }

    // MARK: - Worktree Row

    @ViewBuilder
    private func taskWorktreeRow(_ worktree: Worktree) -> some View {
        let isSelected = worktree.id == selectedWorktreeId
        let worktreeWindows = windows
            .filter { $0.worktreeId == worktree.id }
            .sorted { $0.tmuxWindowIndex < $1.tmuxWindowIndex }
        let shortName = projectMap[worktree.projectId]?.shortName ?? "?"

        VStack(alignment: .leading, spacing: 0) {
            TaskWorktreeRowView(
                worktree: worktree,
                projectShortName: shortName,
                isSelected: isSelected,
                onSelect: { onSelectWorktree(worktree.id) }
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
            }

            // Nested windows under each worktree
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
