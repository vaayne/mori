import Foundation

public struct ToolSettings: Codable, Equatable, Sendable {
    public static let supportedCommands = ["tmux", "lazygit", "yazi"]

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
