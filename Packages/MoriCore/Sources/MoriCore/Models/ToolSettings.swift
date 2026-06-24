import Foundation

public struct ToolSettings: Codable, Equatable, Sendable {
    public static let supportedCommands = ["tmux", "lazygit", "yazi"]

    public var tmuxPath: String
    public var lazygitPath: String
    public var yaziPath: String
    public var applyMoriTmuxDefaults: Bool
    /// Custom base directory for new local worktrees. Empty means use the default `~/.mori`.
    public var worktreeBasePath: String

    public init(
        tmuxPath: String = "",
        lazygitPath: String = "",
        yaziPath: String = "",
        applyMoriTmuxDefaults: Bool = true,
        worktreeBasePath: String = ""
    ) {
        self.tmuxPath = tmuxPath
        self.lazygitPath = lazygitPath
        self.yaziPath = yaziPath
        self.applyMoriTmuxDefaults = applyMoriTmuxDefaults
        self.worktreeBasePath = worktreeBasePath
    }

    private enum CodingKeys: String, CodingKey {
        case tmuxPath
        case lazygitPath
        case yaziPath
        case applyMoriTmuxDefaults
        case worktreeBasePath
    }

    private static let defaultsKey = "toolSettings"

    public static func load(from defaults: UserDefaults = .standard) -> ToolSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let model = try? JSONDecoder().decode(ToolSettings.self, from: data) else {
            return ToolSettings()
        }
        return model
    }

    public static func save(_ model: ToolSettings, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(model) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tmuxPath = try container.decodeIfPresent(String.self, forKey: .tmuxPath) ?? ""
        lazygitPath = try container.decodeIfPresent(String.self, forKey: .lazygitPath) ?? ""
        yaziPath = try container.decodeIfPresent(String.self, forKey: .yaziPath) ?? ""
        applyMoriTmuxDefaults = try container.decodeIfPresent(Bool.self, forKey: .applyMoriTmuxDefaults) ?? true
        worktreeBasePath = try container.decodeIfPresent(String.self, forKey: .worktreeBasePath) ?? ""
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tmuxPath, forKey: .tmuxPath)
        try container.encode(lazygitPath, forKey: .lazygitPath)
        try container.encode(yaziPath, forKey: .yaziPath)
        try container.encode(applyMoriTmuxDefaults, forKey: .applyMoriTmuxDefaults)
        try container.encode(worktreeBasePath, forKey: .worktreeBasePath)
    }

    /// Resolved base directory for new local worktrees, expanding `~` and falling
    /// back to `~/.mori` when no custom path is configured.
    public func resolvedWorktreeBaseDir() -> String {
        let trimmed = worktreeBasePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return (NSHomeDirectory() as NSString).appendingPathComponent(".mori")
        }
        return NSString(string: trimmed).expandingTildeInPath
    }

    public func configuredPath(for command: String) -> String? {
        guard let trimmed = trimmedRawPath(for: command), !trimmed.isEmpty else {
            return nil
        }
        return NSString(string: trimmed).expandingTildeInPath
    }

    public func displayPath(for command: String) -> String {
        if let configuredPath = configuredPath(for: command) {
            return configuredPath
        }
        return BinaryResolver.resolve(command: command) ?? ""
    }

    public func rawPath(for command: String) -> String? {
        switch command {
        case "tmux": tmuxPath
        case "lazygit": lazygitPath
        case "yazi": yaziPath
        default: nil
        }
    }

    public func trimmedRawPath(for command: String) -> String? {
        rawPath(for: command)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public mutating func setRawPath(_ value: String, for command: String) {
        switch command {
        case "tmux":
            tmuxPath = value
        case "lazygit":
            lazygitPath = value
        case "yazi":
            yaziPath = value
        default:
            break
        }
    }
}
