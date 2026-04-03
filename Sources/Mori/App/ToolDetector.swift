import Foundation

/// Detects availability of external CLI tools (lazygit, yazi, etc.) via PATH lookup.
struct ToolDetector: Sendable {

    /// A CLI tool that Mori can launch in a tmux pane.
    struct Tool: Sendable {
        let id: String
        let name: String
        let command: String
        let description: String
        let isAvailable: Bool
    }

    /// Well-known tools that Mori can detect and offer to launch.
    static let knownTools: [(id: String, name: String, command: String, description: String, installHint: String)] = [
        ("lazygit", "Lazygit", "lazygit", "Terminal UI for git", "brew install lazygit"),
        ("yazi", "Yazi", "yazi", "Terminal file manager", "brew install yazi"),
    ]

    /// Detect all known tools and return their availability status.
    static func detectAll() -> [Tool] {
        knownTools.map { tool in
            let available = isInPath(tool.command)
            return Tool(
                id: tool.id,
                name: tool.name,
                command: tool.command,
                description: available ? tool.description : "Not installed — \(tool.installHint)",
                isAvailable: available
            )
        }
    }

    /// Check if a command exists in PATH.
    private static func isInPath(_ command: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
