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

    public func configuredPath(for command: String) -> String? {
        let rawValue: String
        switch command {
        case "tmux": rawValue = tmuxPath
        case "lazygit": rawValue = lazygitPath
        case "yazi": rawValue = yaziPath
        default: return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : NSString(string: trimmed).expandingTildeInPath
    }
}
