import ArgumentParser
import Foundation

/// List local tmux sessions with display-friendly names.
struct Sessions: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List local tmux sessions with display-friendly names."
    )

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() async throws {
        let lister = SessionLister()
        let sessions = try await lister.listSessions()

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(sessions)
            print(String(data: data, encoding: .utf8) ?? "[]")
        } else {
            if sessions.isEmpty {
                print("No tmux sessions found.")
                return
            }
            for session in sessions {
                let attachedMark = session.attached ? " (attached)" : ""
                let windows = session.windowCount == 1 ? "1 window" : "\(session.windowCount) windows"
                print("\(session.displayName)\(attachedMark) — \(windows) [\(session.name)]")
            }
        }
    }
}
