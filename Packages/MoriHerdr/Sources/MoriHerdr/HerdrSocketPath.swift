import Foundation

/// Where a herdr server for a given session listens.
///
/// Mirrors herdr's own resolution: an explicit `HERDR_SOCKET_PATH` wins, otherwise
/// the path is derived from the session name. herdr injects both variables into every
/// pane it manages, so a process started inside a pane can find its own server.
public enum HerdrSocketPath {
    public static let defaultSession = "default"

    /// The config directory herdr uses for a session's runtime state.
    public static func sessionDirectory(session: String, home: String = NSHomeDirectory()) -> String {
        let base = "\(home)/.config/herdr"
        guard session != defaultSession, !session.isEmpty else { return base }
        return "\(base)/sessions/\(session)"
    }

    public static func resolve(session: String, home: String = NSHomeDirectory()) -> String {
        "\(sessionDirectory(session: session, home: home))/herdr.sock"
    }

    /// The socket the surrounding process belongs to, if it is running inside a herdr pane.
    public static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        if let explicit = environment["HERDR_SOCKET_PATH"], !explicit.isEmpty { return explicit }
        guard let session = environment["HERDR_SESSION"], !session.isEmpty else { return nil }
        return resolve(session: session)
    }
}
