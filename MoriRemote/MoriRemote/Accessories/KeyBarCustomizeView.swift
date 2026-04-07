#if os(iOS)
import SwiftUI

/// Bottom sheet for customizing the keyboard accessory key bar.
struct KeyBarCustomizeView: View {
    let keyBar: KeyBarView
    @Environment(\.dismiss) private var dismiss

    @State private var layout: [KeyAction] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "Customize Keys"))
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)

                        Text(String(localized: "Pick the keys you want in the terminal accessory bar. Reorder active keys to keep your most-used actions close."))
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .listRowBackground(Color.clear)
                }

                Section(String(localized: "Active Keys")) {
                    let activeKeys = layout.filter { $0 != .divider }
                    if activeKeys.isEmpty {
                        Text(String(localized: "No keys added"))
                            .foregroundStyle(Theme.textSecondary)
                            .font(.system(size: 13))
                    } else {
                        ForEach(activeKeys, id: \.self) { action in
                            activeKeyRow(action)
                        }
                        .onMove { from, to in
                            var keys = layout.filter { $0 != .divider }
                            keys.move(fromOffsets: from, toOffset: to)
                            applyLayout(keys)
                        }
                        .onDelete { offsets in
                            var keys = layout.filter { $0 != .divider }
                            keys.remove(atOffsets: offsets)
                            applyLayout(keys)
                        }
                    }
                }

                ForEach(KeyAction.Category.allCases, id: \.self) { category in
                    Section(category.localizedTitle) {
                        let actions = KeyAction.actions(for: category)
                        ForEach(actions, id: \.self) { action in
                            keyToggleRow(action)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle(String(localized: "Customize Keys"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Reset")) {
                        applyLayout(KeyAction.defaultLayout)
                    }
                    .foregroundStyle(Theme.destructive)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Done")) { dismiss() }
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

    private func activeKeyRow(_ action: KeyAction) -> some View {
        HStack(spacing: 12) {
            keyPreview(action, width: 52, height: 28)

            Text(action.localizedDescription)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)

            Spacer()
        }
        .padding(.vertical, 2)
        .listRowBackground(Theme.mutedSurface)
    }

    private func keyToggleRow(_ action: KeyAction) -> some View {
        let isInBar = layout.contains(action)
        return Button {
            var newLayout = layout.filter { $0 != .divider }
            if isInBar {
                newLayout.removeAll { $0 == action }
            } else {
                newLayout.append(action)
            }
            applyLayout(newLayout)
        } label: {
            HStack(spacing: 12) {
                keyPreview(action, width: 62, height: 30)

                Text(action.localizedDescription)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)

                Spacer()

                Image(systemName: isInBar ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isInBar ? Theme.accent : Theme.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Theme.mutedSurface)
    }

    private func keyPreview(_ action: KeyAction, width: CGFloat, height: CGFloat) -> some View {
        Text(action.label)
            .font(.system(size: action.isSpecial ? 10 : 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(keyColor(action))
            .frame(width: width, height: height)
            .background(keyBackground(action), in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(keyBorder(action), lineWidth: 1)
            )
    }

    private func keyColor(_ action: KeyAction) -> Color {
        if action.isTmux { return Theme.accent }
        if action.isSpecial { return Theme.textSecondary }
        return Theme.textPrimary
    }

    private func keyBackground(_ action: KeyAction) -> Color {
        if action.isTmux { return Theme.accentSoft }
        if action.isSpecial { return Theme.elevatedBg }
        return Theme.mutedSurface
    }

    private func keyBorder(_ action: KeyAction) -> Color {
        if action.isTmux { return Theme.accentBorder }
        return Theme.cardBorder
    }
}

private extension KeyAction.Category {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .modifiers: return "Modifiers"
        case .symbols: return "Symbols"
        case .navigation: return "Navigation"
        case .functionKeys: return "Function Keys"
        case .tmux: return "Tmux Shortcuts"
        }
    }
}

private extension KeyAction {
    var localizedDescription: String {
        switch self {
        case .esc:        return String(localized: "Escape key")
        case .ctrl:       return String(localized: "Control modifier (sticky)")
        case .alt:        return String(localized: "Alt/Meta modifier")
        case .tab:        return String(localized: "Tab key")
        case .tmuxPrefix:    return String(localized: "Tmux prefix (Ctrl+B)")
        case .tmuxNewTab:    return String(localized: "New tab (⌘T)")
        case .tmuxClosePane: return String(localized: "Close pane (⌘W)")
        case .tmuxNextTab:   return String(localized: "Next tab (⌘⇧])")
        case .tmuxPrevTab:   return String(localized: "Previous tab (⌘⇧[)")
        case .tmuxSplitH:    return String(localized: "Split right (⌘D)")
        case .tmuxSplitV:    return String(localized: "Split down (⌘⇧D)")
        case .tmuxNextPane:  return String(localized: "Next pane (⌘])")
        case .tmuxPrevPane:  return String(localized: "Previous pane (⌘[)")
        case .tmuxZoom:      return String(localized: "Toggle zoom (⌘⇧↩)")
        case .tmuxDetach:    return String(localized: "Detach session")
        case .left:       return String(localized: "Arrow left (auto-repeat)")
        case .down:       return String(localized: "Arrow down (auto-repeat)")
        case .up:         return String(localized: "Arrow up (auto-repeat)")
        case .right:      return String(localized: "Arrow right (auto-repeat)")
        case .home:       return String(localized: "Home key")
        case .end:        return String(localized: "End key")
        case .pageUp:     return String(localized: "Page up")
        case .pageDown:   return String(localized: "Page down")
        default:          return String(localized: "Send key") + " ‘\(label)’"
        }
    }
}
#endif
