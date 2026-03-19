import SwiftUI
import MoriCore

/// A row representing a single tmux window within a worktree section.
public struct WindowRowView: View {
    let window: RuntimeWindow
    let isActive: Bool
    let shortcutIndex: Int?
    let onSelect: () -> Void

    @State private var isHovered = false

    public init(
        window: RuntimeWindow,
        isActive: Bool,
        shortcutIndex: Int? = nil,
        onSelect: @escaping () -> Void
    ) {
        self.window = window
        self.isActive = isActive
        self.shortcutIndex = shortcutIndex
        self.onSelect = onSelect
    }

    public var body: some View {
        Button(action: onSelect) {
            HStack(spacing: MoriTokens.Spacing.md) {
                Image(systemName: window.tag?.symbolName ?? "terminal")
                    .font(MoriTokens.Font.label)
                    .foregroundStyle(isActive ? MoriTokens.Color.active : MoriTokens.Color.muted)

                Text(window.title.isEmpty ? "Window \(window.tmuxWindowIndex)" : window.title)
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
        .onHover { isHovered = $0 }
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
            case .idle:
                EmptyView()
            }
        }
    }
}
