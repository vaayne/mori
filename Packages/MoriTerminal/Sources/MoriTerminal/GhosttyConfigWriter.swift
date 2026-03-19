import Foundation
import MoriCore

/// Writes TerminalSettings to a Ghostty-compatible config file.
/// Config uses Ghostty's `key = value` format, loaded via `ghostty_config_load_file()`.
@MainActor
enum GhosttyConfigWriter {

    private static let configDir: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Mori", isDirectory: true)
    }()

    static let configPath: URL = configDir.appendingPathComponent("ghostty.conf")

    /// Write a Ghostty config file from the given settings. Returns the file path.
    @discardableResult
    static func write(settings: TerminalSettings) -> String {
        let theme = settings.theme
        var lines: [String] = []

        // Font
        lines.append("font-family = \(settings.fontFamily)")
        lines.append("font-size = \(Int(settings.fontSize))")

        // Colors (Ghostty uses rrggbb without # prefix)
        lines.append("foreground = \(stripHash(theme.foreground))")
        lines.append("background = \(stripHash(theme.background))")
        lines.append("cursor-color = \(stripHash(theme.cursor))")
        lines.append("selection-background = \(stripHash(theme.selection))")

        // ANSI palette (16 colors)
        for (i, color) in theme.ansi.enumerated() {
            lines.append("palette = \(i)=#\(stripHash(color))")
        }

        // Cursor style
        switch settings.cursorStyle {
        case .block:
            lines.append("cursor-style = block")
        case .underline:
            lines.append("cursor-style = underline")
        case .bar:
            lines.append("cursor-style = bar")
        }
        lines.append("cursor-style-blink = true")

        // Terminal compatibility
        lines.append("term = xterm-256color")

        // Disable Ghostty's built-in window chrome — Mori manages its own
        lines.append("window-decoration = false")
        lines.append("confirm-close-surface = false")
        lines.append("quit-after-last-window-closed = false")

        let content = lines.joined(separator: "\n") + "\n"

        // Write to disk
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        try? content.write(to: configPath, atomically: true, encoding: .utf8)

        return configPath.path
    }

    private static func stripHash(_ hex: String) -> String {
        hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    }
}
