import Foundation

/// A named terminal color scheme with 16 ANSI colors plus foreground/background/cursor/selection.
/// Colors are stored as hex strings (e.g., "#1e1e2e").
public struct TerminalTheme: Codable, Equatable, Sendable, Identifiable {
    public var id: String { name }

    public let name: String

    // Base colors
    public let foreground: String
    public let background: String
    public let cursor: String
    public let selection: String

    // ANSI 0–15 (black, red, green, yellow, blue, magenta, cyan, white × normal + bright)
    public let ansi: [String]

    public init(
        name: String,
        foreground: String,
        background: String,
        cursor: String,
        selection: String,
        ansi: [String]
    ) {
        precondition(ansi.count == 16, "ANSI palette must contain exactly 16 colors")
        self.name = name
        self.foreground = foreground
        self.background = background
        self.cursor = cursor
        self.selection = selection
        self.ansi = ansi
    }
}

// MARK: - Built-in Themes

extension TerminalTheme {
    public static let builtIn: [TerminalTheme] = [
        .defaultDark, .defaultLight, .solarizedDark, .solarizedLight,
        .dracula, .nord, .oneDark, .tokyoNight, .catppuccinMocha,
    ]

    public static let defaultDark = TerminalTheme(
        name: "Default Dark",
        foreground: "#d4d4d4",
        background: "#1e1e1e",
        cursor: "#aeafad",
        selection: "#264f78",
        ansi: [
            "#000000", "#cd3131", "#0dbc79", "#e5e510",
            "#2472c8", "#bc3fbc", "#11a8cd", "#e5e5e5",
            "#666666", "#f14c4c", "#23d18b", "#f5f543",
            "#3b8eea", "#d670d6", "#29b8db", "#ffffff",
        ]
    )

    public static let defaultLight = TerminalTheme(
        name: "Default Light",
        foreground: "#333333",
        background: "#ffffff",
        cursor: "#333333",
        selection: "#add6ff",
        ansi: [
            "#000000", "#cd3131", "#00bc00", "#949800",
            "#0451a5", "#bc05bc", "#0598bc", "#555555",
            "#666666", "#cd3131", "#14ce14", "#b5ba00",
            "#0451a5", "#bc05bc", "#0598bc", "#a5a5a5",
        ]
    )

    public static let solarizedDark = TerminalTheme(
        name: "Solarized Dark",
        foreground: "#839496",
        background: "#002b36",
        cursor: "#839496",
        selection: "#073642",
        ansi: [
            "#073642", "#dc322f", "#859900", "#b58900",
            "#268bd2", "#d33682", "#2aa198", "#eee8d5",
            "#002b36", "#cb4b16", "#586e75", "#657b83",
            "#839496", "#6c71c4", "#93a1a1", "#fdf6e3",
        ]
    )

    public static let solarizedLight = TerminalTheme(
        name: "Solarized Light",
        foreground: "#657b83",
        background: "#fdf6e3",
        cursor: "#657b83",
        selection: "#eee8d5",
        ansi: [
            "#073642", "#dc322f", "#859900", "#b58900",
            "#268bd2", "#d33682", "#2aa198", "#eee8d5",
            "#002b36", "#cb4b16", "#586e75", "#657b83",
            "#839496", "#6c71c4", "#93a1a1", "#fdf6e3",
        ]
    )

    public static let dracula = TerminalTheme(
        name: "Dracula",
        foreground: "#f8f8f2",
        background: "#282a36",
        cursor: "#f8f8f2",
        selection: "#44475a",
        ansi: [
            "#21222c", "#ff5555", "#50fa7b", "#f1fa8c",
            "#bd93f9", "#ff79c6", "#8be9fd", "#f8f8f2",
            "#6272a4", "#ff6e6e", "#69ff94", "#ffffa5",
            "#d6acff", "#ff92df", "#a4ffff", "#ffffff",
        ]
    )

    public static let nord = TerminalTheme(
        name: "Nord",
        foreground: "#d8dee9",
        background: "#2e3440",
        cursor: "#d8dee9",
        selection: "#434c5e",
        ansi: [
            "#3b4252", "#bf616a", "#a3be8c", "#ebcb8b",
            "#81a1c1", "#b48ead", "#88c0d0", "#e5e9f0",
            "#4c566a", "#bf616a", "#a3be8c", "#ebcb8b",
            "#81a1c1", "#b48ead", "#8fbcbb", "#eceff4",
        ]
    )

    public static let oneDark = TerminalTheme(
        name: "One Dark",
        foreground: "#abb2bf",
        background: "#282c34",
        cursor: "#528bff",
        selection: "#3e4451",
        ansi: [
            "#282c34", "#e06c75", "#98c379", "#e5c07b",
            "#61afef", "#c678dd", "#56b6c2", "#abb2bf",
            "#545862", "#e06c75", "#98c379", "#e5c07b",
            "#61afef", "#c678dd", "#56b6c2", "#c8ccd4",
        ]
    )

    public static let tokyoNight = TerminalTheme(
        name: "Tokyo Night",
        foreground: "#a9b1d6",
        background: "#1a1b26",
        cursor: "#c0caf5",
        selection: "#33467c",
        ansi: [
            "#15161e", "#f7768e", "#9ece6a", "#e0af68",
            "#7aa2f7", "#bb9af7", "#7dcfff", "#a9b1d6",
            "#414868", "#f7768e", "#9ece6a", "#e0af68",
            "#7aa2f7", "#bb9af7", "#7dcfff", "#c0caf5",
        ]
    )

    public static let catppuccinMocha = TerminalTheme(
        name: "Catppuccin Mocha",
        foreground: "#cdd6f4",
        background: "#1e1e2e",
        cursor: "#f5e0dc",
        selection: "#45475a",
        ansi: [
            "#45475a", "#f38ba8", "#a6e3a1", "#f9e2af",
            "#89b4fa", "#f5c2e7", "#94e2d5", "#bac2de",
            "#585b70", "#f38ba8", "#a6e3a1", "#f9e2af",
            "#89b4fa", "#f5c2e7", "#94e2d5", "#a6adc8",
        ]
    )
}
