import Foundation

/// Foundation-only POSIX command assembly. It is kept free of terminal-native
/// types so the SSH transport owns only its grouped-shadow lifecycle.
enum TmuxShellCommand {
    static let fallbackPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    static func command(executable: String, arguments: [String]) -> String {
        let executableToken = quote(executable)
        let argumentTokens = arguments.map(quote).joined(separator: " ")
        return "PATH=\(quote(fallbackPath)):$PATH; export PATH; tmux_path=$(command -v -- \(executableToken)) || exit 127; exec \"$tmux_path\" \(argumentTokens)"
    }

    /// In POSIX shell, a single quote inside a single-quoted word must close the
    /// word, emit a quoted apostrophe, then reopen it: `'"'"'`.
    static func quote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}

struct TmuxVersion: Comparable, Equatable, Sendable {
    let major: Int
    let minor: Int

    static func < (lhs: Self, rhs: Self) -> Bool { (lhs.major, lhs.minor) < (rhs.major, rhs.minor) }

    static func parse(_ output: String) -> TmuxVersion? {
        let fields = output.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace)
        guard fields.count == 2, fields[0] == "tmux" else { return nil }
        let pieces = fields[1].split(separator: ".", maxSplits: 1)
        guard pieces.count == 2, let major = Int(pieces[0]) else { return nil }
        let digits = pieces[1].prefix { $0.isNumber }
        guard !digits.isEmpty, let minor = Int(digits) else { return nil }
        return .init(major: major, minor: minor)
    }
}

enum TmuxCommandError: Error, Equatable, Sendable, LocalizedError {
    case invalidExecutable
    case unsafeArgument
    case malformedVersion
    case unsupportedVersion
    case ownershipMismatch
    case groupMismatch

    var errorDescription: String? {
        switch self {
        case .invalidExecutable:
            String(localized: "The tmux executable must be an absolute path or tmux.")
        case .unsafeArgument:
            String(localized: "The tmux command contains an unsupported control character.")
        case .malformedVersion:
            String(localized: "The tmux version response is invalid.")
        case .unsupportedVersion:
            String(localized: "tmux 3.2 or later is required.")
        case .ownershipMismatch:
            String(localized: "The temporary tmux session could not be verified safely.")
        case .groupMismatch:
            String(localized: "The temporary tmux session is not grouped with the requested workspace.")
        }
    }
}

/// Builds a bare non-login POSIX shell command. Every dynamic token is
/// single-quoted; the only shell expansion is the fixed PATH setup and command
/// resolution. Grouped-shadow cleanup is verified before it can kill anything.
enum TmuxCommandBuilder {
    static func validateExecutable(_ path: String) throws {
        guard path == "tmux" || path.hasPrefix("/") else { throw TmuxCommandError.invalidExecutable }
        try validate(path)
    }

    static func command(executable: String, arguments: [String]) throws -> String {
        try validateExecutable(executable)
        try arguments.forEach(validate)
        return TmuxShellCommand.command(executable: executable, arguments: arguments)
    }

    static func preflight(executable: String) throws -> String { try command(executable: executable, arguments: ["-V"]) }

    static func requireSupportedVersion(_ output: String) throws {
        guard let version = TmuxVersion.parse(output) else { throw TmuxCommandError.malformedVersion }
        guard version >= .init(major: 3, minor: 2) else { throw TmuxCommandError.unsupportedVersion }
    }

    static func shadowName(source: String, runtimeID: UUID) throws -> String {
        try validate(source)
        return "\(source)--mori-remote-\(runtimeID.uuidString.lowercased())"
    }

    static func createShadow(executable: String, source: String, runtimeID: UUID) throws -> String {
        let shadow = try shadowName(source: source, runtimeID: runtimeID)
        return try command(executable: executable, arguments: ["new-session", "-d", "-t", source, "-s", shadow])
    }

    /// `-f` applies flags to the newly attached control client, before it can receive navigation.
    static func attachShadow(executable: String, shadow: String) throws -> String {
        try command(executable: executable, arguments: ["-C", "attach-session", "-t", shadow, "-f", "active-pane,ignore-size"])
    }

    struct ShadowCleanupPlan: Equatable, Sendable {
        let source: String
        let shadow: String
        let runtimeID: UUID
        let verifyCommand: String
        let killCommand: String
    }

    static func cleanupPlan(executable: String, source: String, shadow: String, runtimeID: UUID) throws -> ShadowCleanupPlan {
        let expected = try shadowName(source: source, runtimeID: runtimeID)
        guard shadow == expected else { throw TmuxCommandError.ownershipMismatch }
        let verify = try command(executable: executable, arguments: ["display-message", "-p", "-t", shadow, "#{session_name}\t#{session_group}"])
        let kill = try command(executable: executable, arguments: ["kill-session", "-t", shadow])
        return .init(source: source, shadow: shadow, runtimeID: runtimeID, verifyCommand: verify, killCommand: kill)
    }

    static func verifyCleanup(_ output: String, plan: ShadowCleanupPlan) throws {
        let fields = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\t", omittingEmptySubsequences: false)
        guard fields.count == 2, fields[0] == plan.shadow else { throw TmuxCommandError.ownershipMismatch }
        guard fields[1] == plan.source else { throw TmuxCommandError.groupMismatch }
    }

    private static func validate(_ value: String) throws {
        guard !value.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\0" }) else { throw TmuxCommandError.unsafeArgument }
    }
}
