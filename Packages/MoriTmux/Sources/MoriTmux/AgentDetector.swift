import Foundation

/// Result of detecting a coding agent in a tmux pane.
public struct DetectedAgent: Sendable, Equatable {
    /// The matched process name (e.g. "claude", "codex").
    public let processName: String
    /// Current state inferred from captured terminal output.
    public let state: DetectedAgentState

    public init(processName: String, state: DetectedAgentState) {
        self.processName = processName
        self.state = state
    }
}

/// Identifies coding agents running in tmux panes and detects their state
/// from captured terminal output. Stateless — all methods are static.
public enum AgentDetector {

    /// Process names recognized as coding agents.
    public static let agentProcessNames: Set<String> = [
        "claude", "codex", "omp", "pi", "droid", "amp", "opencode",
    ]

    /// Check if a process name is a known coding agent.
    public static func isAgentProcess(_ command: String?) -> Bool {
        guard let command, !command.isEmpty else { return false }
        return agentProcessNames.contains(command)
    }

    /// Detect a coding agent and its state from pane data.
    /// Checks both `pane_current_command` and the child process map.
    /// Returns nil if the pane is not running a known agent.
    public static func detect(
        pane: TmuxPane,
        capturedOutput: String,
        now: TimeInterval,
        childProcesses: [String: String] = [:]
    ) -> DetectedAgent? {
        // First check pane_current_command directly
        var agentName: String? = nil
        if let command = pane.currentCommand, agentProcessNames.contains(command) {
            agentName = command
        }

        // Fallback: check child processes of pane_pid
        // tmux reports shell as pane_current_command; the agent is a child process
        if agentName == nil, let childName = childProcesses[pane.paneId] {
            agentName = childName
        }

        guard let agentName else { return nil }

        let lines = capturedOutput
            .split(separator: "\n", omittingEmptySubsequences: false)
            .suffix(20)
            .map { String($0) }

        let state = detectState(processName: agentName, lines: lines)
        return DetectedAgent(processName: agentName, state: state)
    }

    /// Scan all running processes and build a map of [paneId: agentProcessName]
    /// for panes whose child process is a known coding agent.
    /// Performs a single `ps` call — O(1) shell invocations regardless of pane count.
    public static func scanForAgentProcesses(
        panes: [(paneId: String, panePid: String)]
    ) -> [String: String] {
        // Build pid -> paneId lookup
        var pidToPaneId: [String: String] = [:]
        for (paneId, panePid) in panes {
            pidToPaneId[panePid] = paneId
        }

        guard !pidToPaneId.isEmpty else { return [:] }

        // Single ps call to get all processes with their parent PID and command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-eo", "ppid,comm"]
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return [:]
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [:] }

        var result: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces)
                .split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let ppid = String(parts[0])
            let comm = String(parts[1])

            // Extract just the binary name from the full path
            let name = comm.split(separator: "/").last.map(String.init) ?? comm

            if let paneId = pidToPaneId[ppid], agentProcessNames.contains(name) {
                result[paneId] = name
            }
        }

        return result
    }

    // MARK: - State Detection

    /// Dispatch to agent-specific or generic state detection.
    static func detectState(processName: String, lines: [String]) -> DetectedAgentState {
        switch processName {
        case "claude":
            return detectClaudeState(lines) ?? detectGenericState(lines)
        case "codex":
            return detectCodexState(lines) ?? detectGenericState(lines)
        case "amp":
            return detectAmpState(lines) ?? detectGenericState(lines)
        default:
            return detectGenericState(lines)
        }
    }

    // MARK: - Claude Code

    /// Claude Code-specific patterns.
    static func detectClaudeState(_ lines: [String]) -> DetectedAgentState? {
        for line in lines.reversed() {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.isEmpty { continue }
            let lower = stripped.lowercased()

            // Waiting: permission prompt, yes/no, or input prompt
            if lower.contains("do you want to proceed") { return .waitingForInput }
            if lower.contains("allow") && lower.contains("deny") { return .waitingForInput }
            if lower.contains("[y/n]") { return .waitingForInput }

            // Completed: cost summary at end of turn
            if lower.contains("total cost:") { return .completed }
            if lower.contains("tokens used:") { return .completed }

            // Only check last few non-empty lines for prompt-like patterns
            if stripped.hasSuffix(">") || line.hasSuffix("> ") { return .waitingForInput }
            break
        }
        return nil
    }

    // MARK: - Codex

    /// Codex-specific patterns.
    static func detectCodexState(_ lines: [String]) -> DetectedAgentState? {
        for line in lines.reversed() {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.isEmpty { continue }
            let lower = stripped.lowercased()

            if lower.contains("approve") && lower.contains("deny") { return .waitingForInput }
            if lower.contains("sandbox") && lower.contains("apply") { return .waitingForInput }
            break
        }
        return nil
    }

    // MARK: - Amp

    /// Amp-specific patterns.
    static func detectAmpState(_ lines: [String]) -> DetectedAgentState? {
        for line in lines.reversed() {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.isEmpty { continue }
            let lower = stripped.lowercased()

            if lower.contains("accept") && lower.contains("reject") { return .waitingForInput }
            break
        }
        return nil
    }

    // MARK: - Generic

    /// Generic fallback detection using patterns shared across agents.
    static func detectGenericState(_ lines: [String]) -> DetectedAgentState {
        // Check error patterns first (scan all lines)
        for line in lines {
            let lower = line.lowercased()
            if lower.contains("error:") || line.contains("FAILED")
                || lower.contains("panic:") || lower.contains("fatal:") {
                return .error
            }
        }

        // Check last non-empty line for prompt patterns
        for line in lines.reversed() {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.isEmpty { continue }
            let lower = stripped.lowercased()

            if line.hasSuffix("> ") || line.hasSuffix("? ") { return .waitingForInput }
            if stripped.hasSuffix(">") || stripped.hasSuffix("?") { return .waitingForInput }
            if lower.contains("waiting for input") { return .waitingForInput }
            if lower.contains("[y/n]") { return .waitingForInput }
            if lower.contains("press any key") { return .waitingForInput }
            break
        }

        // Check completion patterns in tail
        let tail = lines.suffix(5)
        for line in tail {
            let lower = line.lowercased()
            if lower.contains("done") || lower.contains("complete")
                || lower.contains("finished") {
                return .completed
            }
        }

        return .running
    }
}
