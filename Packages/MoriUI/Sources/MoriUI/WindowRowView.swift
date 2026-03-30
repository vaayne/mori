import SwiftUI
import MoriCore

/// A row representing a single tmux window within a worktree section.
public struct WindowRowView: View {
    let window: RuntimeWindow
    let isActive: Bool
    let shortcutIndex: Int?
    let onSelect: () -> Void
    let onRequestPaneOutput: ((String, @escaping (String?) -> Void) -> Void)?

    @State private var isHovered = false
    @State private var showPopover = false
    @State private var popoverOutput: String?
    @State private var hoverTimer: Timer?

    public init(
        window: RuntimeWindow,
        isActive: Bool,
        shortcutIndex: Int? = nil,
        onSelect: @escaping () -> Void,
        onRequestPaneOutput: ((String, @escaping (String?) -> Void) -> Void)? = nil
    ) {
        self.window = window
        self.isActive = isActive
        self.shortcutIndex = shortcutIndex
        self.onSelect = onSelect
        self.onRequestPaneOutput = onRequestPaneOutput
    }

    public var body: some View {
        Button(action: onSelect) {
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
                    Text("\u{2318}\(shortcutIndex)")
                        .font(MoriTokens.Font.monoSmall)
                        .foregroundStyle(MoriTokens.Color.muted)
                        .accessibilityLabel("Command \(shortcutIndex)")
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
        .onHover { hovering in
            isHovered = hovering
            if hovering && window.badge != nil && onRequestPaneOutput != nil {
                hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                    let paneId = window.activePaneId ?? window.tmuxWindowId
                    onRequestPaneOutput?(paneId) { output in
                        DispatchQueue.main.async {
                            self.popoverOutput = output
                            self.showPopover = output != nil
                        }
                    }
                }
            } else {
                hoverTimer?.invalidate()
                hoverTimer = nil
                showPopover = false
                popoverOutput = nil
            }
        }
        .popover(isPresented: $showPopover, arrowEdge: .trailing) {
            if let output = popoverOutput {
                PanePreviewPopover(output: output)
            }
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
                Image(systemName: "exclamationmark.bubble.fill")
                    .font(.system(size: MoriTokens.Icon.badge))
                    .foregroundStyle(MoriTokens.Color.attention)
                    .help("Waiting for input")
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
