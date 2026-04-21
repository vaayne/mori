import SwiftUI
import MoriCore

/// Row view for agent sidebar — shows project/worktree context, agent name, state, last output line.
public struct AgentWindowRowView: View {
    let window: RuntimeWindow
    let projectName: String
    let worktreeName: String
    let isSelected: Bool
    let shortcutIndex: Int?
    let shortcutHintsVisible: Bool
    let onSelect: () -> Void
    let onRequestPaneOutput: ((String, @escaping (String?) -> Void) -> Void)?
    let onSendKeys: ((String, String) -> Void)?

    @EnvironmentObject private var chromePaletteStore: MoriChromePaletteStore
    @State private var isHovered = false
    @State private var showPopover = false
    @State private var popoverOutput: String?
    @State private var isLoadingOutput = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var showReplyField = false

    public init(
        window: RuntimeWindow,
        projectName: String,
        worktreeName: String,
        isSelected: Bool,
        shortcutIndex: Int? = nil,
        shortcutHintsVisible: Bool = false,
        onSelect: @escaping () -> Void,
        onRequestPaneOutput: ((String, @escaping (String?) -> Void) -> Void)? = nil,
        onSendKeys: ((String, String) -> Void)? = nil
    ) {
        self.window = window
        self.projectName = projectName
        self.worktreeName = worktreeName
        self.isSelected = isSelected
        self.shortcutIndex = shortcutIndex
        self.shortcutHintsVisible = shortcutHintsVisible
        self.onSelect = onSelect
        self.onRequestPaneOutput = onRequestPaneOutput
        self.onSendKeys = onSendKeys
    }

    public var body: some View {
        VStack(spacing: 0) {
            rowContent
            replyFieldView
        }
        .onHover { hovering in
            isHovered = hovering
            hoverTask?.cancel()
            if hovering, onRequestPaneOutput != nil {
                hoverTask = Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    isLoadingOutput = true
                    showPopover = true
                    let paneId = window.activePaneId ?? window.tmuxWindowId
                    onRequestPaneOutput?(paneId) { output in
                        self.popoverOutput = output
                        self.isLoadingOutput = false
                        if output == nil {
                            self.showPopover = false
                        }
                    }
                }
            } else {
                showPopover = false
                popoverOutput = nil
                isLoadingOutput = false
            }
        }
        .popover(isPresented: $showPopover, arrowEdge: .trailing) {
            if isLoadingOutput {
                ProgressView()
                    .controlSize(.small)
                    .padding(MoriTokens.Spacing.lg)
            } else if let output = popoverOutput {
                PanePreviewPopover(output: output)
            }
        }
    }

    private var rowContent: some View {
        Button(action: {
                hoverTask?.cancel()
                showPopover = false
                popoverOutput = nil
                isLoadingOutput = false
                onSelect()
            }) {
            HStack(spacing: MoriTokens.Spacing.md) {
                agentIcon

                VStack(alignment: .leading, spacing: MoriTokens.Spacing.xxs) {
                    HStack(spacing: MoriTokens.Spacing.sm) {
                        Text(window.detectedAgent ?? window.title)
                            .font(MoriTokens.Font.windowTitle)
                            .lineLimit(1)
                            .foregroundStyle(isSelected ? Color.primary : MoriTokens.Color.muted)

                        stateBadge
                    }

                    Text("\(projectName)/\(worktreeName)/\(window.title)")
                        .font(MoriTokens.Font.caption)
                        .lineLimit(1)
                        .foregroundStyle(MoriTokens.Color.muted)
                }

                Spacer()

                if let shortcutIndex, shortcutHintsVisible {
                    ShortcutHintPill("⌘\(shortcutIndex)")
                        .transition(.opacity)
                        .accessibilityLabel("Command Option \(shortcutIndex)")
                }

                if window.badge == .waiting, onSendKeys != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showReplyField.toggle()
                        }
                    } label: {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 11))
                            .foregroundStyle(MoriTokens.Color.attention)
                    }
                    .buttonStyle(.plain)
                    .help(String.localized("Reply"))
                }
            }
            .padding(.vertical, MoriTokens.Spacing.md)
            .padding(.horizontal, MoriTokens.Spacing.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: MoriTokens.Radius.small))
        .animation(.easeInOut(duration: 0.14), value: shortcutHintsVisible)
    }

    @ViewBuilder
    private var agentIcon: some View {
        Image(systemName: agentIconName)
            .font(MoriTokens.Font.label)
            .foregroundStyle(agentIconColor)
    }

    private var agentIconName: String {
        switch window.agentState {
        case .running: return "bolt.fill"
        case .waitingForInput: return "exclamationmark.bubble.fill"
        case .error: return "xmark.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .none: return "terminal"
        }
    }

    private var agentIconColor: Color {
        switch window.agentState {
        case .running: return MoriTokens.Color.success
        case .waitingForInput: return MoriTokens.Color.attention
        case .error: return MoriTokens.Color.error
        case .completed: return MoriTokens.Color.success
        case .none: return MoriTokens.Color.muted
        }
    }

    @ViewBuilder
    private var stateBadge: some View {
        switch window.agentState {
        case .running:
            Text(String.localized("Running"))
                .font(MoriTokens.Font.caption)
                .foregroundStyle(MoriTokens.Color.success)
        case .waitingForInput:
            Text(String.localized("Waiting"))
                .font(MoriTokens.Font.caption)
                .foregroundStyle(MoriTokens.Color.attention)
        case .error:
            Text(String.localized("Error"))
                .font(MoriTokens.Font.caption)
                .foregroundStyle(MoriTokens.Color.error)
        case .completed:
            Text(String.localized("Done"))
                .font(MoriTokens.Font.caption)
                .foregroundStyle(MoriTokens.Color.success)
        case .none:
            EmptyView()
        }
    }

    private var rowBackground: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(MoriTokens.Chrome.rowSelectionFill(chromePaletteStore.palette))
        } else if isHovered {
            return AnyShapeStyle(MoriTokens.Chrome.rowHoverFill(chromePaletteStore.palette))
        } else {
            return AnyShapeStyle(Color.clear)
        }
    }

    @ViewBuilder
    private var replyFieldView: some View {
        if showReplyField {
            QuickReplyField(
                onSend: { text in
                    let paneId = window.activePaneId ?? window.tmuxWindowId
                    onSendKeys?(paneId, text + "\n")
                },
                onDismiss: { showReplyField = false }
            )
            .padding(EdgeInsets(top: 0, leading: MoriTokens.Spacing.lg, bottom: MoriTokens.Spacing.xs, trailing: MoriTokens.Spacing.lg))
        }
    }
}
