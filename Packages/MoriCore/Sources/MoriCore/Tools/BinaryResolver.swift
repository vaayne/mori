import Foundation

public enum BinaryResolver {
    public static var defaultSearchDirectories: [String] {
        let home = NSHomeDirectory()
        return [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/opt/local/bin",
            "\(home)/homebrew/bin",
            "\(home)/.homebrew/bin",
            "\(home)/.local/bin",
        ]
    }

    public static func resolve(
        command: String,
        configuredPath: String? = nil,
        bundledPath: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        additionalSearchDirectories: [String] = defaultSearchDirectories,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        if let configuredPath {
            let expanded = NSString(string: configuredPath).expandingTildeInPath
            if isExecutable(expanded) {
                return expanded
            }
        }

        if let bundledPath, isExecutable(bundledPath) {
            return bundledPath
        }

        var seen = Set<String>()

        for directory in additionalSearchDirectories {
            let expanded = NSString(string: directory).expandingTildeInPath
            let candidate = expanded.hasSuffix("/\(command)") ? expanded : "\(expanded)/\(command)"
            if seen.insert(candidate).inserted, isExecutable(candidate) {
                return candidate
            }
        }

        guard let pathVar = environment["PATH"] else { return nil }
        for directory in pathVar.split(separator: ":") {
            let expanded = NSString(string: String(directory)).expandingTildeInPath
            let candidate = "\(expanded)/\(command)"
            if seen.insert(candidate).inserted, isExecutable(candidate) {
                return candidate
            }
        }

        return nil
    }

    public static func exists(
        command: String,
        configuredPath: String? = nil,
        bundledPath: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        additionalSearchDirectories: [String] = defaultSearchDirectories,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> Bool {
        resolve(
            command: command,
            configuredPath: configuredPath,
            bundledPath: bundledPath,
            environment: environment,
            additionalSearchDirectories: additionalSearchDirectories,
            isExecutable: isExecutable
        ) != nil
    }
}
