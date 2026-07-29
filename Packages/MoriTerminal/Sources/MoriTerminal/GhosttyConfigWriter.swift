#if os(macOS)
import Foundation

/// Writes minimal Mori-specific overrides to a Ghostty config file.
/// User preferences (font, theme, cursor, keybindings, etc.) come from
/// Ghostty's own config at `~/.config/ghostty/config`.
@MainActor
enum GhosttyConfigWriter {

    /// Write Mori's default preferences, loaded *before* the user's config so any
    /// value the user sets in ~/.config/ghostty/config wins (ghostty keeps the
    /// last value it reads). Overrides that must beat the user's config belong
    /// in `write(appSupportDirectory:)` instead.
    @discardableResult
    static func writeDefaults(appSupportDirectory: URL) -> String {
        let configFilePath = appSupportDirectory.appendingPathComponent("ghostty-mori-defaults.conf")

        let lines: [String] = [
            "# Mori default preferences — do not edit manually.",
            "# Loaded before ~/.config/ghostty/config, so your own config overrides these.",
            "window-padding-x = 16",
            "window-padding-y = 12",
            "window-padding-color = extend",
        ]

        let content = lines.joined(separator: "\n") + "\n"
        try? FileManager.default.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
        try? content.write(to: configFilePath, atomically: true, encoding: .utf8)
        return configFilePath.path
    }

    /// Write Mori-specific embedding overrides. Returns the file path.
    /// - Parameter appSupportDirectory: The directory where the config file should be written.
    /// - Returns: The path to the written config file.
    @discardableResult
    static func write(appSupportDirectory: URL) -> String {
        let configFilePath = appSupportDirectory.appendingPathComponent("ghostty-mori-overrides.conf")

        let lines: [String] = [
            "# Mori embedding overrides — do not edit manually.",
            "# User preferences belong in ~/.config/ghostty/config",
            "window-decoration = false",
            "confirm-close-surface = false",
            "quit-after-last-window-closed = false",
            "# Override ghostty's default xterm-ghostty for tmux compatibility",
            "term = xterm-256color",
        ]

        let content = lines.joined(separator: "\n") + "\n"
        try? FileManager.default.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
        try? content.write(to: configFilePath, atomically: true, encoding: .utf8)
        return configFilePath.path
    }

    /// Write a single-theme override used only when extracting chrome colors for a
    /// resolved split-theme variant. Returns the file path. Loaded last so it wins
    /// over the user's split `theme` value. Not used for the terminal's own config,
    /// which keeps the split theme so libghostty can switch variants live.
    @discardableResult
    static func writeThemeOverride(appSupportDirectory: URL, theme: String) -> String {
        let configFilePath = appSupportDirectory.appendingPathComponent("ghostty-mori-theme.conf")
        let content = "# Mori resolved-theme override — do not edit manually.\ntheme = \(theme)\n"
        try? FileManager.default.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
        try? content.write(to: configFilePath, atomically: true, encoding: .utf8)
        return configFilePath.path
    }
}
#endif
