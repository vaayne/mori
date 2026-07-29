import Foundation

/// Which herdr server a process should talk to.
///
/// Mori runs its own named session with its own config file so that the user's `default`
/// session and `~/.config/herdr/config.toml` are never touched — Mori's chrome-off config
/// would otherwise ruin herdr as a standalone tool. Every process Mori starts that should
/// join that session — the server, the client rendering in the terminal surface, the agent
/// hooks — gets its identity from here, so there is exactly one definition of it.
public struct HerdrEnvironment: Sendable, Hashable {
    /// The session name Mori claims. Anything but `default`, which belongs to the user.
    public static let defaultSession = "mori"

    public let session: String
    public let configPath: String

    public init(session: String = HerdrEnvironment.defaultSession, configPath: String) {
        self.session = session
        self.configPath = configPath
    }

    public var socketPath: String { HerdrSocketPath.resolve(session: session) }

    /// The variables that bind a process to this session.
    public var variables: [String: String] {
        ["HERDR_SESSION": session, "HERDR_CONFIG_PATH": configPath]
    }

    public func apply(to environment: [String: String]) -> [String: String] {
        environment.merging(variables) { _, new in new }
    }

    /// The same bindings as shell `export` lines, for the scripts Mori generates.
    public var shellExports: [String] {
        variables.sorted { $0.key < $1.key }.map { "export \($0.key)=\(shellQuoted($0.value))" }
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
