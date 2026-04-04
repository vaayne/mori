import SwiftUI
import MoriCore

/// A row representing a single tmux window within a worktree section.
public struct WindowRowView: View {
    let window: RuntimeWindow
    let isActive: Bool
    let shortcutIndex: Int?
    let shortcutHintsVisible: Bool
    let onSelect: () -> Void
    let onRequestPaneOutput: ((String, @escaping (String?) -> Void) -> Void)?
    let onSendKeys: ((String, String) -> Void)?

    @State private var isHovered = false
    @State private var showPopover = false
    @State private var popoverOutput: String?
    @State private var isLoadingOutput = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var showReplyField = false

    public init(
        window: RuntimeWindow,
        isActive: Bool,
        shortcutIndex: Int? = nil,
        shortcutHintsVisible: Bool = false,
        onSelect: @escaping () -> Void,
        onRequestPaneOutput: ((String, @escaping (String?) -> Void) -> Void)? = nil,
        onSendKeys: ((String, String) -> Void)? = nil
    ) {
        self.window = window
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
            if hovering, window.badge != nil, onRequestPaneOutput != nil {
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

    private var rowButton: some View {
        Button(action: {
                hoverTask?.cancel()
                showPopover = false
                popoverOutput = nil
                isLoadingOutput = false
                onSelect()
            }) {
            HStack(spacing: MoriTokens.Spacing.md) {
                Image(systemName: window.tag?.symbolName ?? "terminal")
                    .font(MoriTokens.Font.label)
                    .foregroundStyle(isActive ? MoriTokens.Color.active : MoriTokens.Color.muted)

                Text(window.title.isEmpty ? .localized("Window \(window.tmuxWindowIndex)") : window.title)
                    .font(MoriTokens.Font.windowTitle)
                    .lineLimit(1)
                    .foregroundStyle(isActive ? Color.primary : MoriTokens.Color.muted)

                Spacer()

                if let shortcutIndex {
                    if shortcutHintsVisible {
                        ShortcutHintPill("\u{2318}\(shortcutIndex)")
                            .transition(.opacity)
                            .accessibilityLabel("Command \(shortcutIndex)")
                    } else {
                        Text("\u{2318}\(shortcutIndex)")
                            .font(MoriTokens.Font.monoSmall)
                            .foregroundStyle(MoriTokens.Color.muted)
                            .accessibilityLabel("Command \(shortcutIndex)")
                    }
                }

                windowBadgeView

                if isActive {
                    Circle()
                        .fill(MoriTokens.Color.active)
                        .frame(width: MoriTokens.Icon.indicator, height: MoriTokens.Icon.indicator)
                        .accessibilityLabel("Active window")
                }
            }
            .padding(.vertical, MoriTokens.Spacing.xs)
            .padding(.horizontal, MoriTokens.Spacing.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: MoriTokens.Radius.small))
        .animation(.easeInOut(duration: 0.14), value: shortcutHintsVisible)
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

    private var rowBackground: some ShapeStyle {
        if isActive {
            return AnyShapeStyle(MoriTokens.Color.active.opacity(MoriTokens.Opacity.subtle))
        } else if isHovered {
            return AnyShapeStyle(MoriTokens.Color.muted.opacity(MoriTokens.Opacity.subtle))
        } else {
            return AnyShapeStyle(Color.clear)
        }
    }

    @ViewBuilder
    private var windowBadgeView: some View {
        if let badge = window.badge {
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
