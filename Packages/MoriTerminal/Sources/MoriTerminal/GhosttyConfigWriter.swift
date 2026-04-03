#if os(macOS)
import Foundation

/// Writes minimal Mori-specific overrides to a Ghostty config file.
/// User preferences (font, theme, cursor, keybindings, etc.) come from
/// Ghostty's own config at `~/.config/ghostty/config`.
@MainActor
enum GhosttyConfigWriter {

    /// Write Mori-specific embedding overrides. Returns the file path.
    /// - Parameter appSupportDirectory: The directory where the config file should be written.
    ///   Defaults to `~/Library/Application Support/Mori` for backwards compatibility.
    ///   Callers should pass `MoriPaths.appSupportDirectory` for proper dev/prod isolation.
    /// - Returns: The path to the written config file.
    @discardableResult
    static func write(appSupportDirectory: URL? = nil) -> String {
        let configDir: URL
        if let providedDir = appSupportDirectory {
            configDir = providedDir
        } else {
            // Fallback for backwards compatibility
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            configDir = appSupport.appendingPathComponent("Mori", isDirectory: true)
        }
        
        let configFilePath = configDir.appendingPathComponent("ghostty-mori-overrides.conf")
        
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
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        try? content.write(to: configFilePath, atomically: true, encoding: .utf8)
        return configFilePath.path
    }
}
#endif
