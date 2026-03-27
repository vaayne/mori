import CryptoKit
import Darwin
import Foundation

public struct SSHExecutionConfig: Sendable {
    public let host: String
    public let user: String?
    public let port: Int?
    public let sshOptions: [String]
    public let askpassPassword: String?

    public init(
        host: String,
        user: String? = nil,
        port: Int? = nil,
        sshOptions: [String] = [],
        askpassPassword: String? = nil
    ) {
        self.host = host
        self.user = user
        self.port = port
        self.sshOptions = sshOptions
        self.askpassPassword = askpassPassword
    }

    public var target: String {
        if let user, !user.isEmpty {
            return "\(user)@\(host)"
        }
        return host
    }
}

public enum SSHCommandSupportError: Error, LocalizedError, Sendable {
    case askPassScriptCreateFailed(String)
    case askPassScriptWriteFailed(String)
    case askPassScriptPermissionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .askPassScriptCreateFailed(let message):
            return "Failed to create SSH askpass script: \(message)"
        case .askPassScriptWriteFailed(let message):
            return "Failed to write SSH askpass script: \(message)"
        case .askPassScriptPermissionFailed(let message):
            return "Failed to secure SSH askpass script: \(message)"
        }
    }
}

public struct SSHAskPassScript: Sendable {
    public let path: String

    public func cleanup() {
        try? FileManager.default.removeItem(atPath: path)
    }
}

public enum SSHCommandSupport {
    public static let connectTimeoutSeconds = 8
    public static let serverAliveIntervalSeconds = 5
    public static let serverAliveCountMax = 3
    public static let remoteCommandTimeoutSeconds = 60
    public static let bootstrapTimeoutSeconds = 20

    public static func controlSocketPath(
        endpointKey: String,
        temporaryDirectory: String = NSTemporaryDirectory()
    ) -> String {
        let hash = SHA256.hash(data: Data(endpointKey.utf8)).map { String(format: "%02x", $0) }.joined()
        let suffix = String(hash.prefix(20))
        let filename = "mori_ssh_\(suffix).sock"
        let preferred = (temporaryDirectory as NSString).appendingPathComponent(filename)
        if preferred.utf8.count < 100 {
            return preferred
        }
        return "/tmp/\(filename)"
    }

    public static func connectivityOptions() -> [String] {
        [
            "-o", "ConnectTimeout=\(connectTimeoutSeconds)",
            "-o", "ServerAliveInterval=\(serverAliveIntervalSeconds)",
            "-o", "ServerAliveCountMax=\(serverAliveCountMax)",
        ]
    }

    public static func removingBatchMode(from options: [String]) -> [String] {
        var filtered: [String] = []
        var i = 0
        while i < options.count {
            if options[i] == "-o", i + 1 < options.count, options[i + 1].hasPrefix("BatchMode=") {
                i += 2
                continue
            }
            filtered.append(options[i])
            i += 1
        }
        return filtered
    }

    public static func shellEscape(_ value: String) -> String {
        if value.isEmpty {
            return "''"
        }
        let escaped = value.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }

    public static func createAskPassScript(password: String) throws -> SSHAskPassScript {
        let temporaryDirectory = NSTemporaryDirectory()
        let templatePath = (temporaryDirectory as NSString).appendingPathComponent("mori-askpass-XXXXXX")
        var template = templatePath.utf8CString
        let fd = template.withUnsafeMutableBufferPointer { buffer -> Int32 in
            guard let baseAddress = buffer.baseAddress else { return -1 }
            return mkstemp(baseAddress)
        }
        guard fd >= 0 else {
            throw SSHCommandSupportError.askPassScriptCreateFailed("mkstemp errno \(errno)")
        }

        let path = template.withUnsafeBufferPointer { buffer -> String in
            let base = UnsafeRawPointer(buffer.baseAddress!).assumingMemoryBound(to: CChar.self)
            return String(cString: base)
        }

        let script = "#!/bin/sh\nprintf '%s\\n' \(singleQuoted(password))\n"
        do {
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
            try handle.write(contentsOf: Data(script.utf8))
            if fchmod(fd, 0o700) != 0 {
                let message = "fchmod errno \(errno)"
                _ = close(fd)
                try? FileManager.default.removeItem(atPath: path)
                throw SSHCommandSupportError.askPassScriptPermissionFailed(message)
            }
            _ = close(fd)
            return SSHAskPassScript(path: path)
        } catch let error as SSHCommandSupportError {
            throw error
        } catch {
            _ = close(fd)
            try? FileManager.default.removeItem(atPath: path)
            throw SSHCommandSupportError.askPassScriptWriteFailed(error.localizedDescription)
        }
    }

    public static func askPassEnvironment(
        scriptPath: String,
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        let allowlist = [
            "PATH", "HOME", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE",
            "USER", "LOGNAME", "SHELL",
        ]
        var environment: [String: String] = [:]
        for key in allowlist {
            if let value = baseEnvironment[key], !value.isEmpty {
                environment[key] = value
            }
        }
        environment["SSH_ASKPASS"] = scriptPath
        environment["SSH_ASKPASS_REQUIRE"] = "force"
        environment["DISPLAY"] = "mori"
        return environment
    }

    private static func singleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}
