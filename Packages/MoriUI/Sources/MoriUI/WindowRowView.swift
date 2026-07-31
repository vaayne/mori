import SwiftUI
import MoriCore

/// A row representing a single tmux pane within a worktree section.
/// For single-pane windows (`pane` nil or the window's only pane) the row reads
/// exactly like the old window row — the window name is the meaningful label.
/// Panes of split windows each get their own row: agent panes show their
/// hook-assigned pane title, plain shells show "window · N" (pane titles for
/// shells are usually just the hostname), and state derives from the pane.
public struct WindowRowView: View {
    let window: RuntimeWindow
    let pane: RuntimePane?
    let paneIndex: Int?
    let isActive: Bool
    let shortcutIndex: Int?
    let shortcutHintsVisible: Bool
    let onSelect: () -> Void
    let onRequestPaneOutput: ((String, @escaping (String?) -> Void) -> Void)?
    let onSendKeys: ((String, String) -> Void)?

    /// Whether this row represents one pane of a split window (vs a whole window).
    private var isSplitPaneRow: Bool { pane != nil && window.paneCount > 1 }

    @State private var isHovered = false
    @State private var showPopover = false
    @State private var popoverOutput: String?
    @State private var isLoadingOutput = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var showReplyField = false

    public init(
        window: RuntimeWindow,
        pane: RuntimePane? = nil,
        paneIndex: Int? = nil,
        isActive: Bool,
        shortcutIndex: Int? = nil,
        shortcutHintsVisible: Bool = false,
        onSelect: @escaping () -> Void,
        onRequestPaneOutput: ((String, @escaping (String?) -> Void) -> Void)? = nil,
        onSendKeys: ((String, String) -> Void)? = nil
    ) {
        self.window = window
        self.pane = pane
        self.paneIndex = paneIndex
        self.isActive = isActive
        self.shortcutIndex = shortcutIndex
        self.shortcutHintsVisible = shortcutHintsVisible
        self.onSelect = onSelect
        self.onRequestPaneOutput = onRequestPaneOutput
        self.onSendKeys = onSendKeys
    }

    public var body: some View {
        VStack(spacing: 0) {
            rowButton
            replyFieldView
        }
        .onHover { hovering in
            isHovered = hovering
            hoverTask?.cancel()
            if hovering, rowBadge != nil, onRequestPaneOutput != nil {
                hoverTask = Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    isLoadingOutput = true
                    showPopover = true
                    let paneId = pane?.tmuxPaneId ?? window.activePaneId ?? window.tmuxWindowId
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

    private var rowButton: some View {
        Button(action: {
                hoverTask?.cancel()
                showPopover = false
                popoverOutput = nil
                isLoadingOutput = false
                onSelect()
            }) {
            HStack(spacing: MoriTokens.Spacing.md) {
                // Small SF Symbol glyph in the same family as the worktree row,
                // tinted by state — keeps the two levels visually related.
                Image(systemName: windowGlyph)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(windowGlyphColor)
                    .frame(width: 14, height: 14)
                    .symbolEffect(.pulse, options: .repeating, isActive: rowAgentState == .waitingForInput)

                Text(rowTitle)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(isActive ? Color.primary : Color.primary.opacity(0.72))

                Spacer()

                windowBadgeView

                if let shortcutIndex {
                    if shortcutHintsVisible {
                        ShortcutHintPill("⌘\(shortcutIndex)")
                            .transition(.opacity)
                            .accessibilityLabel("Command Option \(shortcutIndex)")
                    } else {
                        Text("⌘\(shortcutIndex)")
                            .font(MoriTokens.Font.monoShortcut)
                            .foregroundStyle(MoriTokens.Color.inactive)
                            .accessibilityLabel("Command Option \(shortcutIndex)")
                    }
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, MoriTokens.Spacing.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: MoriTokens.Radius.small))
        .animation(.easeInOut(duration: 0.14), value: shortcutHintsVisible)
    }

    /// Agent state driving this row's glyph and pulse: the pane's own state for
    /// split-window rows, the window aggregate otherwise (window detection is
    /// richer for single-pane windows — process scan on top of hook state).
    private var rowAgentState: AgentState {
        isSplitPaneRow ? (pane?.agentState ?? .none) : window.agentState
    }

    private var rowDetectedAgent: String? {
        isSplitPaneRow ? pane?.detectedAgent : window.detectedAgent
    }

    private var rowTitle: String {
        let windowTitle = window.title.isEmpty
            ? String.localized("Window \(window.tmuxWindowIndex)")
            : window.title
        guard isSplitPaneRow, let pane else { return windowTitle }
        if rowDetectedAgent != nil || rowAgentState != .none,
           let title = pane.title, !title.isEmpty {
            return title
        }
        return "\(windowTitle) · \(paneIndex ?? 1)"
    }

    /// Badge for this row. Split-window rows derive it from the pane's agent
    /// state, with the window's unread dot carried by the active pane only so
    /// one window's unread doesn't light every pane row.
    private var rowBadge: WindowBadge? {
        guard isSplitPaneRow, let pane else { return window.badge }
        return StatusAggregator.windowBadge(
            hasUnreadOutput: pane.isActive && window.hasUnreadOutput,
            isRunning: false,
            isLongRunning: false,
            agentState: pane.agentState
        )
    }

    /// Glyph for the row: a node graph for agent-ish rows, a split rectangle
    /// for plain panes of split windows, terminal icon otherwise. Matches the
    /// language used on worktree rows.
    private var windowGlyph: String {
        if rowDetectedAgent != nil || rowAgentState != .none || window.tag == .agent {
            return "point.3.connected.trianglepath.dotted"
        }
        if window.tag == .server { return "server.rack" }
        if isSplitPaneRow { return "rectangle.split.2x1" }
        return "terminal"
    }

    private var windowGlyphColor: Color {
        switch rowAgentState {
        case .error: return MoriTokens.Color.error
        case .waitingForInput: return MoriTokens.Color.attention
        case .running, .completed: return MoriTokens.Color.success
        case .none:
            if isActive { return MoriTokens.Color.active }
            return MoriTokens.Color.inactive
        }
    }

    @ViewBuilder
    private var replyFieldView: some View {
        if showReplyField {
            QuickReplyField(
                onSend: { text in
                    let paneId = pane?.tmuxPaneId ?? window.activePaneId ?? window.tmuxWindowId
                    onSendKeys?(paneId, text + "\n")
                },
                onDismiss: { showReplyField = false }
            )
            .padding(EdgeInsets(top: 0, leading: MoriTokens.Spacing.lg, bottom: MoriTokens.Spacing.xs, trailing: MoriTokens.Spacing.lg))
        }
    }

    private var rowBackground: some ShapeStyle {
        if isActive {
            return AnyShapeStyle(MoriTokens.Color.active.opacity(MoriTokens.Opacity.light))
        } else if isHovered {
            return AnyShapeStyle(Color.primary.opacity(MoriTokens.Opacity.subtle))
        } else {
            return AnyShapeStyle(Color.clear)
        }
    }

    @ViewBuilder
    private var windowBadgeView: some View {
        if let badge = rowBadge {
            switch badge {
            case .error:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: MoriTokens.Icon.badge))
                    .foregroundStyle(MoriTokens.Color.error)
                    .help("Error")
                    .accessibilityLabel("Error")
            case .waiting:
                Button(action: {
                    if onSendKeys != nil {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showReplyField.toggle()
                        }
                    }
                }) {
                    Image(systemName: "exclamationmark.bubble.fill")
                        .font(.system(size: MoriTokens.Icon.badge))
                        .foregroundStyle(MoriTokens.Color.attention)
                }
                .buttonStyle(.plain)
                .help("Waiting for input — click to reply")
                .accessibilityLabel("Waiting for input")
            case .longRunning:
                Image(systemName: "clock.fill")
                    .font(.system(size: MoriTokens.Icon.badge))
                    .foregroundStyle(MoriTokens.Color.warning)
                    .help("Long running")
                    .accessibilityLabel("Long running")
            case .running:
                Image(systemName: "bolt.fill")
                    .font(.system(size: MoriTokens.Icon.badge))
                    .foregroundStyle(MoriTokens.Color.success)
                    .help("Running")
                    .accessibilityLabel("Running")
            case .unread:
                Circle()
                    .fill(MoriTokens.Color.info)
                    .frame(width: MoriTokens.Icon.dot, height: MoriTokens.Icon.dot)
                    .help("Unread output")
                    .accessibilityLabel("Unread output")
            case .agentDone:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: MoriTokens.Icon.badge))
                    .foregroundStyle(MoriTokens.Color.success)
                    .help("Agent completed")
                    .accessibilityLabel("Agent completed")
            case .idle:
                EmptyView()
            }
        }
    }
}
