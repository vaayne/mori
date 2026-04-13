import Foundation
import MoriCore

/// Detects availability of external CLI tools (lazygit, yazi, etc.) via configured
/// paths, common package-manager prefixes, and PATH lookup.
struct ToolDetector: Sendable {

    /// A CLI tool that Mori can launch in a tmux pane.
    struct Tool: Sendable {
        let id: String
        let name: String
        let command: String
        let description: String
        let isAvailable: Bool
        let resolvedCommand: String?
    }

    /// Well-known tools that Mori can detect and offer to launch.
    static let knownTools: [(id: String, name: String, command: String, description: String, installHint: String)] = [
        ("lazygit", "Lazygit", "lazygit", "Terminal UI for git", "brew install lazygit"),
        ("yazi", "Yazi", "yazi", "Terminal file manager", "brew install yazi"),
    ]

    /// Detect all known tools and return their availability status.
    static func detectAll() -> [Tool] {
        let settings = ToolSettings.load()
        return knownTools.map { tool in
            let resolvedCommand = BinaryResolver.resolve(
                command: tool.command,
                configuredPath: settings.configuredPath(for: tool.command)
            )
            let available = resolvedCommand != nil
            return Tool(
                id: tool.id,
                name: tool.name,
                command: tool.command,
                description: available ? tool.description : "Not installed — \(tool.installHint)",
                isAvailable: available,
                resolvedCommand: resolvedCommand
            )
        }
    }
}
