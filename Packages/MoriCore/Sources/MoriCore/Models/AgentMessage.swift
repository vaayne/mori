import Foundation

/// Envelope format for agent-to-agent messages sent via `mori pane message`.
/// Format: `[mori-bridge from:<project>/<worktree>/<window> pane:<id>] <text>`
public struct AgentMessage: Codable, Sendable, Equatable {
    public let fromProject: String
    public let fromWorktree: String
    public let fromWindow: String
    public let fromPaneId: String
    public let text: String

    public init(
        fromProject: String,
        fromWorktree: String,
        fromWindow: String,
        fromPaneId: String,
        text: String
    ) {
        self.fromProject = fromProject
        self.fromWorktree = fromWorktree
        self.fromWindow = fromWindow
        self.fromPaneId = fromPaneId
        self.text = text
    }

    /// Format the message as the wire envelope string.
    public var envelope: String {
        "[mori-bridge from:\(fromProject)/\(fromWorktree)/\(fromWindow) pane:\(fromPaneId)] \(text)"
    }

    /// Parse an envelope string back into an `AgentMessage`.
    /// Returns nil if the string doesn't match the expected format.
    public static func parse(_ string: String) -> AgentMessage? {
        // Pattern: [mori-bridge from:<project>/<worktree>/<window> pane:<id>] <text>
        guard string.hasPrefix("[mori-bridge from:") else { return nil }
        guard let closeBracket = string.firstIndex(of: "]") else { return nil }

        let header = string[string.index(string.startIndex, offsetBy: 18)..<closeBracket]
        let remaining = string[string.index(after: closeBracket)...]
        let text = remaining.trimmingCharacters(in: .whitespaces)

        // Split header into "project/worktree/window pane:id"
        let parts = header.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return nil }

        let addressParts = parts[0].split(separator: "/", maxSplits: 2)
        guard addressParts.count == 3 else { return nil }

        let paneStr = String(parts[1])
        guard paneStr.hasPrefix("pane:") else { return nil }
        let paneId = String(paneStr.dropFirst(5))

        return AgentMessage(
            fromProject: String(addressParts[0]),
            fromWorktree: String(addressParts[1]),
            fromWindow: String(addressParts[2]),
            fromPaneId: paneId,
            text: text
        )
    }
}
