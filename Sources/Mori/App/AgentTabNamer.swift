import MoriTmux

/// Auto-renames tmux windows when coding agents are detected.
/// Tracks original names and restores them when agents exit.
@MainActor
final class AgentTabNamer {

    private let tmuxBackend: TmuxBackend

    /// Original window names before agent rename: [windowId: originalName]
    private var originalNames: [String: String] = [:]

    /// Emoji + label for each known agent process name.
    static let agentLabels: [String: String] = [
        "claude": "🤖 claude",
        "codex": "🧠 codex",
        "omp": "🥧 pi",
        "pi": "🥧 pi",
        "droid": "🤖 droid",
        "amp": "⚡ amp",
        "opencode": "💻 opencode",
    ]

    /// Display name for notifications.
    static let agentDisplayNames: [String: String] = [
        "claude": "Claude Code",
        "codex": "Codex",
        "omp": "Pi",
        "pi": "Pi",
        "droid": "Droid",
        "amp": "Amp",
        "opencode": "OpenCode",
    ]

    init(tmuxBackend: TmuxBackend) {
        self.tmuxBackend = tmuxBackend
    }

    /// Update tab name based on detected agent.
    /// - Parameters:
    ///   - windowId: tmux window ID (e.g. "@0")
    ///   - sessionId: tmux session ID
    ///   - currentTitle: current tmux window name
    ///   - agentProcess: detected agent process name, or nil if no agent
    func update(
        windowId: String,
        sessionId: String,
        currentTitle: String,
        agentProcess: String?
    ) async {
        if let agentProcess, let label = Self.agentLabels[agentProcess] {
            // Agent detected — rename if not already
            if currentTitle != label {
                if originalNames[windowId] == nil {
                    originalNames[windowId] = currentTitle
                }
                try? await tmuxBackend.renameWindow(
                    sessionId: sessionId,
                    windowId: windowId,
                    newName: label
                )
            }
        } else if let originalName = originalNames.removeValue(forKey: windowId) {
            // Agent gone — restore original name
            try? await tmuxBackend.renameWindow(
                sessionId: sessionId,
                windowId: windowId,
                newName: originalName
            )
        }
    }

    /// Clean up tracking for windows that no longer exist.
    func pruneStaleEntries(activeWindowIds: Set<String>) {
        for key in originalNames.keys where !activeWindowIds.contains(key) {
            originalNames.removeValue(forKey: key)
        }
    }
}
