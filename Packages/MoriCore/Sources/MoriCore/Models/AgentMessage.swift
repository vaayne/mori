import Foundation

/// Envelope format for agent-to-agent messages sent via `mori pane message`.
/// Format: `[mori-bridge project:<project> worktree:<worktree> window:<window> pane:<id>] <text>`
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
    /// Uses labeled fields to avoid ambiguity with `/` in worktree/branch names.
    public var envelope: String {
        "[mori-bridge project:\(fromProject) worktree:\(fromWorktree) window:\(fromWindow) pane:\(fromPaneId)] \(text)"
    }

    /// Parse an envelope string back into an `AgentMessage`.
    /// Returns nil if the string doesn't match the expected format.
    public static func parse(_ string: String) -> AgentMessage? {
        // Pattern: [mori-bridge project:<p> worktree:<w> window:<win> pane:<id>] <text>
        let prefix = "[mori-bridge "
        guard string.hasPrefix(prefix) else { return nil }
        guard let closeBracket = string.firstIndex(of: "]") else { return nil }

        let header = String(string[string.index(string.startIndex, offsetBy: prefix.count)..<closeBracket])
        let remaining = string[string.index(after: closeBracket)...]
        let text = remaining.trimmingCharacters(in: .whitespaces)

        // Parse labeled fields from header
        var fields: [String: String] = [:]
        var current = header[...]
        while !current.isEmpty {
            current = current.drop(while: { $0 == " " })
            guard let colonIdx = current.firstIndex(of: ":") else { break }
            let key = String(current[current.startIndex..<colonIdx])
            let afterColon = current[current.index(after: colonIdx)...]
            // Value runs until the next " key:" pattern or end of string
            let value: String
            let rest: Substring
            if let nextField = afterColon.range(of: #" (?:project|worktree|window|pane):"#, options: .regularExpression) {
                value = String(afterColon[afterColon.startIndex..<nextField.lowerBound])
                rest = afterColon[nextField.lowerBound...]
            } else {
                value = String(afterColon)
                rest = afterColon[afterColon.endIndex...]
            }
            fields[key] = value
            current = rest
        }

        guard let project = fields["project"],
              let worktree = fields["worktree"],
              let window = fields["window"],
              let paneId = fields["pane"] else { return nil }

        return AgentMessage(
            fromProject: project,
            fromWorktree: worktree,
            fromWindow: window,
            fromPaneId: paneId,
            text: text
        )
    }
}
