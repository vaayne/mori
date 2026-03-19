import Foundation

/// Reads and writes the user's ghostty config file (`~/.config/ghostty/config`),
/// preserving comments, blank lines, and keys not managed by the settings UI.
@MainActor
public final class GhosttyConfigFile {

    public static let configPath: String = {
        NSHomeDirectory() + "/.config/ghostty/config"
    }()

    /// Parsed line from the config file.
    private enum Line {
        case comment(String)       // "# comment" or blank line
        case keyValue(String, String, String) // key, value, original line text
    }

    private var lines: [Line] = []

    public init() {
        load()
    }

    // MARK: - Read

    /// Get a config value by key. Returns nil if not set.
    public func get(_ key: String) -> String? {
        for line in lines {
            if case .keyValue(let k, let v, _) = line, k == key {
                return v
            }
        }
        return nil
    }

    /// Get all values for a repeatable key (e.g., "keybind").
    public func getAll(_ key: String) -> [String] {
        lines.compactMap { line in
            if case .keyValue(let k, let v, _) = line, k == key {
                return v
            }
            return nil
        }
    }

    // MARK: - Write

    /// Set a config value. Updates existing key or appends if new.
    public func set(_ key: String, value: String) {
        // Update first occurrence
        for i in lines.indices {
            if case .keyValue(let k, _, _) = lines[i], k == key {
                lines[i] = .keyValue(key, value, "\(key) = \(value)")
                return
            }
        }
        // Append new key
        lines.append(.keyValue(key, value, "\(key) = \(value)"))
    }

    /// Remove a key from the config.
    public func remove(_ key: String) {
        lines.removeAll { line in
            if case .keyValue(let k, _, _) = line, k == key {
                return true
            }
            return false
        }
    }

    // MARK: - Persistence

    /// Load from disk.
    public func load() {
        lines = []
        guard FileManager.default.fileExists(atPath: Self.configPath),
              let content = try? String(contentsOfFile: Self.configPath, encoding: .utf8)
        else { return }

        for rawLine in content.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            // Blank or comment
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                lines.append(.comment(rawLine))
                continue
            }

            // key = value
            if let eqIndex = trimmed.firstIndex(of: "=") {
                let key = trimmed[trimmed.startIndex..<eqIndex]
                    .trimmingCharacters(in: .whitespaces)
                let value = trimmed[trimmed.index(after: eqIndex)...]
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                lines.append(.keyValue(key, value, rawLine))
            } else {
                // Unparseable — keep as comment
                lines.append(.comment(rawLine))
            }
        }
    }

    /// Save to disk, preserving structure.
    public func save() {
        let dir = (Self.configPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let content = lines.map { line in
            switch line {
            case .comment(let text): return text
            case .keyValue(_, _, let original): return original
            }
        }.joined(separator: "\n")

        try? content.write(toFile: Self.configPath, atomically: true, encoding: .utf8)
    }

    /// List available ghostty theme names from the app bundle.
    public static func availableThemes() -> [String] {
        let searchPaths = [
            "/Applications/Ghostty.app/Contents/Resources/ghostty/themes",
            "/opt/homebrew/share/ghostty/themes",
            NSHomeDirectory() + "/.config/ghostty/themes",
        ]

        for path in searchPaths {
            if let entries = try? FileManager.default.contentsOfDirectory(atPath: path) {
                return entries.sorted()
            }
        }
        return []
    }
}
