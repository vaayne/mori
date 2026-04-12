import SwiftUI

struct SidebarFooterView: View {
    let shortcutHintsVisible: Bool
    let onAddProject: (() -> Void)?
    let onOpenCommandPalette: (() -> Void)?
    let onOpenSettings: (() -> Void)?
    let horizontalDividerPadding: CGFloat?

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
            Group {
                if let horizontalDividerPadding {
                    Divider()
                        .padding(.horizontal, horizontalDividerPadding)
                } else {
                    Divider()
                }
            }

            HStack(spacing: MoriTokens.Spacing.xl) {
                if let onAddProject {
                    Button(action: onAddProject) {
                        Image(systemName: "plus.rectangle.on.folder")
                            .font(.system(size: 13))
                            .foregroundStyle(MoriTokens.Color.muted)
                    }
                    .buttonStyle(.plain)
                    .help(String.localized("Add Repository"))
                    .accessibilityLabel(String.localized("Add Repository"))
                }

                Spacer()

                if let onOpenCommandPalette {
                    Button(action: onOpenCommandPalette) {
                        Image(systemName: "text.magnifyingglass")
                            .font(.system(size: 13))
                            .foregroundStyle(MoriTokens.Color.muted)
                    }
                    .buttonStyle(.plain)
                    .help(String.localized("Command Palette (⇧⌘P)"))
                    .accessibilityLabel(String.localized("Command Palette"))
                    .overlay(alignment: .top) {
                        if shortcutHintsVisible {
                            ShortcutHintPill("⇧⌘P")
                                .offset(y: -22)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.14), value: shortcutHintsVisible)
                }

                if let onOpenSettings {
                    Button(action: onOpenSettings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13))
                            .foregroundStyle(MoriTokens.Color.muted)
                    }
                    .buttonStyle(.plain)
                    .help(String.localized("Settings (⌘,)"))
                    .accessibilityLabel(String.localized("Settings"))
                    .overlay(alignment: .top) {
                        if shortcutHintsVisible {
                            ShortcutHintPill("⌘,")
                                .offset(y: -22)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.14), value: shortcutHintsVisible)
                }
            }
            .padding(.horizontal, MoriTokens.Spacing.xl)
            .padding(.vertical, MoriTokens.Spacing.lg)
        }
    }
}
