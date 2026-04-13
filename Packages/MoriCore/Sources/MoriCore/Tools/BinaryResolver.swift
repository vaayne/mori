import Foundation

public enum BinaryResolver {
    public static var defaultSearchDirectories: [String] {
        uniqueDirectories(
            from: [
                pathDirectories(from: launchctlPath()),
                pathDirectories(from: pathHelperPath()),
            ]
        )
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

    static func pathDirectories(from pathValue: String?) -> [String] {
        guard let pathValue else { return [] }
        return pathValue
            .split(separator: ":")
            .map { NSString(string: String($0)).expandingTildeInPath }
            .filter { !$0.isEmpty }
    }

    private static func uniqueDirectories(from groups: [[String]]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for directory in groups.joined() {
            if seen.insert(directory).inserted {
                result.append(directory)
            }
        }
        return result
    }

    private static func launchctlPath() -> String? {
        runAndCapture(
            executablePath: "/bin/launchctl",
            arguments: ["getenv", "PATH"]
        )?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func pathHelperPath() -> String? {
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
