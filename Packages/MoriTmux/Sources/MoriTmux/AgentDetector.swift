import Foundation

/// Minimal agent detection utilities.
/// State detection is now handled by hook scripts that set tmux pane options.
/// This file only retains the process name set for reference.
public enum AgentDetector {

    /// Process names recognized as coding agents.
    public static let agentProcessNames: Set<String> = [
        "claude", "codex", "omp", "pi", "droid", "amp", "opencode",
    ]
}
