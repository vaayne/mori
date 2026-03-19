import Foundation

/// Minimal terminal settings placeholder.
/// User-facing terminal configuration (font, theme, cursor, keybindings) is now
/// managed entirely through Ghostty's native config at `~/.config/ghostty/config`.
/// This type is retained only for backward compatibility with UserDefaults cleanup.
public struct TerminalSettings: Codable, Equatable, Sendable {

    public init() {}

    // MARK: - UserDefaults Cleanup

    private static let defaultsKey = "terminalSettings"
    nonisolated(unsafe) private static let defaults = UserDefaults(suiteName: "com.mori.app")!

    /// Remove any previously persisted terminal settings from UserDefaults.
    public static func clearLegacy() {
        defaults.removeObject(forKey: defaultsKey)
    }
}
