import Foundation
import MoriRemoteProtocol
import MoriTmux

/// Lists local tmux sessions with display-friendly names using `SessionNaming.parse()`.
struct SessionLister: Sendable {

    private let runner = TmuxCommandRunner()

    /// List all tmux sessions, returning `SessionInfo` with display-friendly names.
    func listSessions() async throws -> [SessionInfo] {
        let output = try await runner.run(
            "list-sessions", "-F", TmuxParser.sessionFormat
        )

        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return []
        }

        let sessions = TmuxParser.parseSessions(output)

        return sessions.map { session in
            let displayName: String
            if let parsed = SessionNaming.parse(session.name) {
                // Mori convention: project/branch -> "Project / Branch"
                displayName = "\(parsed.projectShortName) / \(parsed.branchSlug)"
            } else {
                // Non-Mori session: use raw name
                displayName = session.name
            }

            return SessionInfo(
                name: session.name,
                displayName: displayName,
                windowCount: session.windowCount,
                attached: session.isAttached
            )
        }
    }
}
