import SwiftUI
import MoriCore

/// A row representing a single tmux window within a worktree section.
public struct WindowRowView: View {
    let window: RuntimeWindow
    let isActive: Bool
    let onSelect: () -> Void

    public init(
        window: RuntimeWindow,
        isActive: Bool,
        onSelect: @escaping () -> Void
    ) {
        self.window = window
        self.isActive = isActive
        self.onSelect = onSelect
    }

    public var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Image(systemName: window.tag?.symbolName ?? "terminal")
                    .font(.caption)
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)

                Text(window.title.isEmpty ? "Window \(window.tmuxWindowIndex)" : window.title)
                    .font(.body)
                    .lineLimit(1)

                Spacer()

                windowBadgeView

                if isActive {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private var windowBadgeView: some View {
        if window.hasUnreadOutput {
            Circle()
                .fill(Color.blue)
                .frame(width: 6, height: 6)
                .help("Unread output")
        } else if let badge = window.badge {
            switch badge {
            case .error:
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                    .help("Error")
            case .running:
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                    .help("Running")
            case .waiting:
                Circle()
                    .fill(Color.yellow)
                    .frame(width: 6, height: 6)
                    .help("Waiting")
            case .unread:
                Circle()
                    .fill(Color.blue)
                    .frame(width: 6, height: 6)
                    .help("Unread")
            case .longRunning:
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                    .help("Long running")
            case .idle:
                EmptyView()
            }
        }
    }
}
