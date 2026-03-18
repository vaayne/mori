import SwiftUI
import MoriCore

/// Sidebar showing worktrees as sections with their tmux windows as rows.
public struct WorktreeSidebarView: View {
    private let worktrees: [Worktree]
    private let windows: [RuntimeWindow]
    private let selectedWorktreeId: UUID?
    private let selectedWindowId: String?
    private let onSelectWorktree: (UUID) -> Void
    private let onSelectWindow: (String) -> Void
    private let onCreateWorktree: ((String) -> Void)?
    private let onRemoveWorktree: ((UUID) -> Void)?

    @State private var isCreatingWorktree = false
    @State private var newBranchName = ""
    @State private var isSubmitting = false

    public init(
        worktrees: [Worktree],
        windows: [RuntimeWindow],
        selectedWorktreeId: UUID?,
        selectedWindowId: String?,
        onSelectWorktree: @escaping (UUID) -> Void,
        onSelectWindow: @escaping (String) -> Void,
        onCreateWorktree: ((String) -> Void)? = nil,
        onRemoveWorktree: ((UUID) -> Void)? = nil
    ) {
        self.worktrees = worktrees
        self.windows = windows
        self.selectedWorktreeId = selectedWorktreeId
        self.selectedWindowId = selectedWindowId
        self.onSelectWorktree = onSelectWorktree
        self.onSelectWindow = onSelectWindow
        self.onCreateWorktree = onCreateWorktree
        self.onRemoveWorktree = onRemoveWorktree
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header with "+" button
            sidebarHeader

            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: MoriTokens.Spacing.sm) {
                    if isCreatingWorktree {
                        branchNameInput
                    }
                    if worktrees.isEmpty && !isCreatingWorktree {
                        emptyState
                    } else {
                        ForEach(worktrees) { worktree in
                            worktreeSection(worktree)
                        }
                    }
                }
                .padding(.vertical, MoriTokens.Spacing.lg)
                .padding(.horizontal, MoriTokens.Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var sidebarHeader: some View {
        HStack {
            Text("Worktrees")
                .font(MoriTokens.Font.sectionTitle)
                .foregroundStyle(MoriTokens.Color.muted)

            Spacer()

            if onCreateWorktree != nil {
                Button(action: {
                    isCreatingWorktree = true
                    newBranchName = ""
                }) {
                    Image(systemName: "plus")
                        .font(MoriTokens.Font.label)
                        .foregroundStyle(MoriTokens.Color.muted)
                }
                .buttonStyle(.plain)
                .help("Create new worktree")
            }
        }
        .padding(.horizontal, MoriTokens.Spacing.xl)
        .padding(.vertical, MoriTokens.Spacing.md)
    }

    // MARK: - Branch Name Input

    private var branchNameInput: some View {
        HStack(spacing: MoriTokens.Spacing.sm) {
            if isSubmitting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "arrow.triangle.branch")
                    .font(MoriTokens.Font.label)
                    .foregroundStyle(MoriTokens.Color.muted)
            }

            TextField("Branch name", text: $newBranchName)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .disabled(isSubmitting)
                .onSubmit {
                    submitBranchName()
                }

            Button(action: { submitBranchName() }) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(MoriTokens.Color.success)
            }
            .buttonStyle(.plain)
            .disabled(newBranchName.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)

            Button(action: { cancelCreation() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(MoriTokens.Color.muted)
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)
        }
        .padding(.horizontal, MoriTokens.Spacing.lg)
        .padding(.vertical, MoriTokens.Spacing.sm)
        .background(MoriTokens.Color.muted.opacity(MoriTokens.Opacity.subtle))
        .clipShape(RoundedRectangle(cornerRadius: MoriTokens.Radius.small))
        .padding(.horizontal, MoriTokens.Spacing.sm)
    }

    private func submitBranchName() {
        let trimmed = newBranchName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        onCreateWorktree?(trimmed)
        isCreatingWorktree = false
        isSubmitting = false
        newBranchName = ""
    }

    private func cancelCreation() {
        isCreatingWorktree = false
        newBranchName = ""
    }

    // MARK: - Sections

    @ViewBuilder
    private func worktreeSection(_ worktree: Worktree) -> some View {
        VStack(alignment: .leading, spacing: MoriTokens.Spacing.xs) {
            WorktreeRowView(
                worktree: worktree,
                isSelected: worktree.id == selectedWorktreeId,
                onSelect: { onSelectWorktree(worktree.id) }
            )
            .contextMenu {
                if !worktree.isMainWorktree, let onRemove = onRemoveWorktree {
                    Button(role: .destructive) {
                        onRemove(worktree.id)
                    } label: {
                        Label("Remove Worktree...", systemImage: "trash")
                    }
                }
            }

            let worktreeWindows = windows
                .filter { $0.worktreeId == worktree.id }
                .sorted { $0.tmuxWindowIndex < $1.tmuxWindowIndex }

            ForEach(worktreeWindows) { window in
                WindowRowView(
                    window: window,
                    isActive: window.tmuxWindowId == selectedWindowId,
                    onSelect: { onSelectWindow(window.tmuxWindowId) }
                )
                .padding(.leading, MoriTokens.Spacing.xxl)
            }
        }
        .padding(.bottom, MoriTokens.Spacing.sm)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: MoriTokens.Spacing.lg) {
            Image(systemName: "folder.badge.plus")
                .font(.title2)
                .foregroundStyle(MoriTokens.Color.muted)
            Text("No worktrees")
                .font(.subheadline)
                .foregroundStyle(MoriTokens.Color.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, MoriTokens.Spacing.emptyState)
    }
}
