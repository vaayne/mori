#if os(iOS)
import SwiftUI

/// Bottom sheet for customizing the keyboard accessory key bar.
/// Users toggle keys on/off. Changes apply live to the key bar.
struct KeyBarCustomizeView: View {
    /// Direct reference to the UIKit key bar — mutations apply immediately.
    let keyBar: KeyBarView
    @Environment(\.dismiss) private var dismiss

    /// Local copy of layout for SwiftUI reactivity.
    @State private var layout: [KeyAction] = []

    var body: some View {
        NavigationStack {
            List {
                Section("Current Bar") {
                    currentBarPreview
                }

                ForEach(KeyAction.Category.allCases, id: \.self) { category in
                    Section(category.rawValue) {
                        let actions = KeyAction.actions(for: category)
                        ForEach(actions, id: \.self) { action in
                            keyToggleRow(action)
                        }
                    }
                }
            }
            .navigationTitle("Customize Keys")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        applyLayout(KeyAction.defaultLayout)
                    }
                    .foregroundStyle(Theme.destructive)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            layout = keyBar.layout
        }
    }

    private func applyLayout(_ newLayout: [KeyAction]) {
        layout = newLayout
        keyBar.layout = newLayout
        KeyBarLayout.save(newLayout)
    }

    // MARK: - Current Bar Preview

    private var currentBarPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(layout.enumerated()), id: \.offset) { _, action in
                    if action == .divider {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 1, height: 22)
                    } else {
                        Text(action.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(keyColor(action))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(keyBackground(action), in: RoundedRectangle(cornerRadius: 5))
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Toggle Row

    private func keyToggleRow(_ action: KeyAction) -> some View {
        let isInBar = layout.contains(action)
        return Button {
            var newLayout = layout
            if isInBar {
                newLayout.removeAll { $0 == action }
            } else {
                // Insert before the last divider or at end
                if let lastDivider = newLayout.lastIndex(of: .divider) {
                    newLayout.insert(action, at: lastDivider)
                } else {
                    newLayout.append(action)
                }
            }
            applyLayout(newLayout)
        } label: {
            HStack {
                Text(action.label)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(keyColor(action))
                    .frame(width: 60, height: 30)
                    .background(keyBackground(action), in: RoundedRectangle(cornerRadius: 6))

                Text(actionDescription(action))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Image(systemName: isInBar ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isInBar ? Theme.accent : .secondary)
            }
        }
    }

    // MARK: - Helpers

    private func keyColor(_ action: KeyAction) -> Color {
        if action.isTmux { return Color(Theme.accent) }
        if action.isSpecial { return .white.opacity(0.55) }
        return .white
    }

    private func keyBackground(_ action: KeyAction) -> Color {
        if action.isTmux { return Color(Theme.accent).opacity(0.1) }
        if action.isSpecial { return Color(red: 0.118, green: 0.118, blue: 0.149) }
        return Color(red: 0.165, green: 0.165, blue: 0.196)
    }

    private func actionDescription(_ action: KeyAction) -> String {
        switch action {
        case .esc:        return "Escape key"
        case .ctrl:       return "Control modifier (sticky)"
        case .alt:        return "Alt/Meta modifier"
        case .tab:        return "Tab key"
        case .tmuxPrefix:    return "Tmux prefix (Ctrl+B)"
        case .tmuxNewTab:    return "New tab (⌘T)"
        case .tmuxClosePane: return "Close pane (⌘W)"
        case .tmuxNextTab:   return "Next tab (⌘⇧])"
        case .tmuxPrevTab:   return "Previous tab (⌘⇧[)"
        case .tmuxSplitH:    return "Split right (⌘D)"
        case .tmuxSplitV:    return "Split down (⌘⇧D)"
        case .tmuxNextPane:  return "Next pane (⌘])"
        case .tmuxPrevPane:  return "Previous pane (⌘[)"
        case .tmuxZoom:      return "Toggle zoom (⌘⇧↩)"
        case .tmuxDetach:    return "Detach session"
        case .left:       return "Arrow left (auto-repeat)"
        case .down:       return "Arrow down (auto-repeat)"
        case .up:         return "Arrow up (auto-repeat)"
        case .right:      return "Arrow right (auto-repeat)"
        case .home:       return "Home key"
        case .end:        return "End key"
        case .pageUp:     return "Page up"
        case .pageDown:   return "Page down"
        default:          return "Send '\(action.label)'"
        }
    }
}
#endif
