import SwiftUI

struct SidebarFooterView: View {
    private let shortcutHintsVisible: Bool
    private let onAddProject: (() -> Void)?
    private let onOpenCommandPalette: (() -> Void)?
    private let onOpenSettings: (() -> Void)?
    private let horizontalDividerPadding: CGFloat?

    init(
        shortcutHintsVisible: Bool,
        onAddProject: (() -> Void)? = nil,
        onOpenCommandPalette: (() -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil,
        horizontalDividerPadding: CGFloat? = nil
    ) {
        self.shortcutHintsVisible = shortcutHintsVisible
        self.onAddProject = onAddProject
        self.onOpenCommandPalette = onOpenCommandPalette
        self.onOpenSettings = onOpenSettings
        self.horizontalDividerPadding = horizontalDividerPadding
    }

    var body: some View {
        VStack(spacing: 0) {
            footerDivider

            HStack(spacing: MoriTokens.Spacing.xl) {
                if let onAddProject {
                    footerButton(
                        systemImage: "plus.rectangle.on.folder",
                        helpText: String.localized("Add Repository"),
                        accessibilityLabel: String.localized("Add Repository"),
                        action: onAddProject
                    )
                }

                Spacer()

                if let onOpenCommandPalette {
                    footerButton(
                        systemImage: "text.magnifyingglass",
                        helpText: String.localized("Command Palette (⇧⌘P)"),
                        accessibilityLabel: String.localized("Command Palette"),
                        shortcutHint: "⇧⌘P",
                        action: onOpenCommandPalette
                    )
                }

                if let onOpenSettings {
                    footerButton(
                        systemImage: "gearshape",
                        helpText: String.localized("Settings (⌘,)"),
                        accessibilityLabel: String.localized("Settings"),
                        shortcutHint: "⌘,",
                        action: onOpenSettings
                    )
                }
            }
            .padding(.horizontal, MoriTokens.Spacing.xl)
            .padding(.vertical, MoriTokens.Spacing.lg)
        }
    }

    @ViewBuilder
    private var footerDivider: some View {
        if let horizontalDividerPadding {
            Divider()
                .padding(.horizontal, horizontalDividerPadding)
        } else {
            Divider()
        }
    }

    private func footerButton(
        systemImage: String,
        helpText: String,
        accessibilityLabel: String,
        shortcutHint: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(MoriTokens.Color.muted)
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel(accessibilityLabel)
        .overlay(alignment: .top) {
            if let shortcutHint, shortcutHintsVisible {
                ShortcutHintPill(shortcutHint)
                    .offset(y: -22)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.14), value: shortcutHintsVisible)
    }
}
