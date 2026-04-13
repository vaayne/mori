import Foundation

#if os(macOS)
private enum BinaryResolverHostEnvironment {
    static func launchctlPath() -> String? {
        runAndCapture(
            executablePath: "/bin/launchctl",
            arguments: ["getenv", "PATH"]
        )?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func pathHelperPath() -> String? {
        guard let output = runAndCapture(
            executablePath: "/usr/libexec/path_helper",
            arguments: ["-s"]
        ) else {
            return nil
        }

        for line in output.split(separator: "\n") {
            let text = String(line)
            guard let start = text.range(of: "PATH=\"")?.upperBound,
                  let end = text[start...].firstIndex(of: "\"") else { continue }
            return String(text[start..<end])
        }
        return nil
    }

    private static func runAndCapture(executablePath: String, arguments: [String]) -> String? {
        let process = Process()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
#endif

public enum BinaryResolver {
    #if os(macOS)
    private static let cachedDefaultSearchDirectories: [String] = uniqueDirectories(
        from: [
            pathDirectories(from: BinaryResolverHostEnvironment.launchctlPath()),
            pathDirectories(from: BinaryResolverHostEnvironment.pathHelperPath()),
            explicitFallbackDirectories,
        ]
    )
    #endif

    private static let explicitFallbackDirectories: [String] = uniqueDirectories(
        from: [[
            "~/homebrew/bin",
            "~/.homebrew/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/opt/local/bin",
            "~/.local/bin",
            "~/.nix-profile/bin",
            "/nix/var/nix/profiles/default/bin",
            "~/.local/share/mise/shims",
            "~/.asdf/shims",
            "~/.cargo/bin",
            "~/bin",
        ]]
    )

    public static func configuredPath(
        for command: String,
        settings: ToolSettings = ToolSettings.load()
    ) -> String? {
        settings.configuredPath(for: command)
    }

    public static func resolveTool(
        command: String,
        settings: ToolSettings = ToolSettings.load(),
        bundledPath: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        additionalSearchDirectories: [String] = defaultSearchDirectories,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        resolve(
            command: command,
            configuredPath: configuredPath(for: command, settings: settings),
            bundledPath: bundledPath,
            environment: environment,
            additionalSearchDirectories: additionalSearchDirectories,
            isExecutable: isExecutable
        )
    }

    public static var defaultSearchDirectories: [String] {
        #if os(macOS)
        return cachedDefaultSearchDirectories
        #else
        return explicitFallbackDirectories
        #endif
    }

    public static func synthesizedPATH(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        additionalSearchDirectories: [String] = defaultSearchDirectories
    ) -> String {
        uniqueDirectories(
            from: [
                pathDirectories(from: environment["PATH"]),
                additionalSearchDirectories,
            ]
        ).joined(separator: ":")
    }

    public static func synthesizedEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        additionalSearchDirectories: [String] = defaultSearchDirectories
    ) -> [String: String] {
        var merged = environment
        let pathValue = synthesizedPATH(
            environment: environment,
            additionalSearchDirectories: additionalSearchDirectories
        )
        if !pathValue.isEmpty {
            merged["PATH"] = pathValue
        }
        return merged
    }

    public static func resolve(
        command: String,
        configuredPath: String? = nil,
        bundledPath: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        additionalSearchDirectories: [String] = defaultSearchDirectories,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        if let configuredPath = validatedExecutablePath(configuredPath, isExecutable: isExecutable) {
            return configuredPath
        }

        if let bundledPath = validatedExecutablePath(bundledPath, isExecutable: isExecutable) {
            return bundledPath
        }

        if let resolvedPath = firstExecutablePath(
            for: command,
            searchDirectories: pathDirectories(from: environment["PATH"]),
            isExecutable: isExecutable
        ) {
            return resolvedPath
        }

        return firstExecutablePath(
            for: command,
            searchDirectories: additionalSearchDirectories,
            isExecutable: isExecutable
        )
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

    public static func toolExists(
        command: String,
        settings: ToolSettings = ToolSettings.load(),
        bundledPath: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        additionalSearchDirectories: [String] = defaultSearchDirectories,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> Bool {
        resolveTool(
            command: command,
            settings: settings,
            bundledPath: bundledPath,
            environment: environment,
            additionalSearchDirectories: additionalSearchDirectories,
            isExecutable: isExecutable
        ) != nil
    }

    public static func pathDirectories(from pathValue: String?) -> [String] {
        guard let pathValue else { return [] }
        return pathValue
            .split(separator: ":")
            .map { NSString(string: String($0)).expandingTildeInPath }
            .filter { !$0.isEmpty }
    }

    private static func validatedExecutablePath(
        _ path: String?,
        isExecutable: (String) -> Bool
    ) -> String? {
        guard let path else { return nil }
        let expandedPath = NSString(string: path).expandingTildeInPath
        guard isExecutable(expandedPath) else { return nil }
        return expandedPath
    }

    private static func firstExecutablePath(
        for command: String,
        searchDirectories: [String],
        isExecutable: (String) -> Bool
    ) -> String? {
        var seen = Set<String>()

        for directory in searchDirectories {
            let candidate = executablePath(for: command, in: directory)
            guard seen.insert(candidate).inserted else { continue }
            if isExecutable(candidate) {
                return candidate
            }
        }

        return nil
    }

    private static func executablePath(for command: String, in directory: String) -> String {
        let expandedDirectory = NSString(string: directory).expandingTildeInPath
        if expandedDirectory.hasSuffix("/\(command)") {
            return expandedDirectory
        }
        return "\(expandedDirectory)/\(command)"
    }

    private static func uniqueDirectories(from groups: [[String]]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for directory in groups.joined() {
            let expanded = NSString(string: directory).expandingTildeInPath
            guard !expanded.isEmpty, seen.insert(expanded).inserted else { continue }
            result.append(expanded)
        }
        return result
    }
}
