import Foundation

public struct ToolSettings: Codable, Equatable, Sendable {
    public var tmuxPath: String
    public var lazygitPath: String
    public var yaziPath: String

    public init(
        tmuxPath: String = "",
        lazygitPath: String = "",
        yaziPath: String = ""
    ) {
        self.tmuxPath = tmuxPath
        self.lazygitPath = lazygitPath
        self.yaziPath = yaziPath
    }

    private static let defaultsKey = "toolSettings"

    public static func load(from defaults: UserDefaults = .standard) -> ToolSettings {
        let model: ToolSettings
        if let data = defaults.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(ToolSettings.self, from: data) {
            model = decoded
        } else {
            model = ToolSettings()
        }
        return model.withResolvedDefaults()
    }

    public static func save(_ model: ToolSettings, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(model) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    public func configuredPath(for command: String) -> String? {
        let trimmed = rawPath(for: command)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : NSString(string: trimmed).expandingTildeInPath
    }

    private func rawPath(for command: String) -> String? {
        switch command {
        case "tmux": tmuxPath
        case "lazygit": lazygitPath
        case "yazi": yaziPath
        default: nil
        }
    }

    private func withResolvedDefaults() -> ToolSettings {
        ToolSettings(
            tmuxPath: resolvedDefault(for: "tmux", current: tmuxPath),
            lazygitPath: resolvedDefault(for: "lazygit", current: lazygitPath),
            yaziPath: resolvedDefault(for: "yazi", current: yaziPath)
        )
    }

    private func resolvedDefault(for command: String, current: String) -> String {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return current }
        return BinaryResolver.resolve(command: command) ?? ""
    }
}
