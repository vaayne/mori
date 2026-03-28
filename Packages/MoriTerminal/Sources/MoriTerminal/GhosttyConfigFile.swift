#if os(macOS)
import Foundation

/// Reads and writes the user's ghostty config file (`~/.config/ghostty/config`),
/// preserving comments, blank lines, and keys not managed by the settings UI.
@MainActor
public final class GhosttyConfigFile {

    public static let configPath: String = {
        NSHomeDirectory() + "/.config/ghostty/config"
    }()

    /// Ensure the ghostty config file exists on disk.
    public static func ensureConfigFileExists() {
        let fm = FileManager.default
        let dir = (configPath as NSString).deletingLastPathComponent
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: configPath) {
            fm.createFile(atPath: configPath, contents: Data())
        }
    }

    /// Remove executable permission bits so the config is always treated as text.
    public static func normalizePermissions() {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: configPath),
              let mode = attrs[.posixPermissions] as? NSNumber else { return }
        let current = mode.intValue
        let normalized = current & ~0o111
        if normalized != current {
            try? fm.setAttributes([.posixPermissions: normalized], ofItemAtPath: configPath)
        }
    }

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
        Self.ensureConfigFileExists()

        let content = lines.map { line in
            switch line {
            case .comment(let text): return text
            case .keyValue(_, _, let original): return original
            }
        }.joined(separator: "\n")

        try? content.write(toFile: Self.configPath, atomically: true, encoding: .utf8)
        Self.normalizePermissions()
    }

    /// Set all values for a repeatable key, replacing all existing entries.
    public func setAll(_ key: String, values: [String]) {
        // Remove all existing entries for this key
        lines.removeAll { line in
            if case .keyValue(let k, _, _) = line, k == key { return true }
            return false
        }
        // Append new entries
        for value in values {
            lines.append(.keyValue(key, value, "\(key) = \(value)"))
        }
    }

    /// List ghostty default keybindings by running `ghostty +list-keybinds`.
    /// Returns array of "key=action" strings.
    public static func defaultKeybinds() -> [String] {
        let process = Process()
        let pipe = Pipe()

        // Try common paths for ghostty binary
        let paths = ["/usr/local/bin/ghostty", "/opt/homebrew/bin/ghostty", "/Applications/Ghostty.app/Contents/MacOS/ghostty"]
        var binaryPath: String?
        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                binaryPath = path
                break
            }
        }
        guard let binary = binaryPath else { return [] }

        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["+list-keybinds"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        return output.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { line in
                // Parse "keybind = key=action" → "key=action"
                if line.hasPrefix("keybind = ") {
                    return String(line.dropFirst("keybind = ".count))
                }
                return line
            }
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
#endif
