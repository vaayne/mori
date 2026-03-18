import Foundation

/// Detects pane state from tmux pane metadata and captured terminal output.
/// Uses pattern matching on the last lines of output to infer agent state,
/// and command name + start time to determine running/idle/long-running.
public enum PaneStateDetector {

    /// Shell process names that indicate the pane is idle (no user command running).
    public static let shellCommands: Set<String> = [
        "bash", "zsh", "fish", "sh", "-bash", "-zsh",
    ]

    /// Long-running threshold in seconds.
    public static let longRunningThreshold: TimeInterval = 30

    /// Detect the state of a pane from its metadata and captured output.
    ///
    /// - Parameters:
    ///   - pane: The tmux pane with current command and start time.
    ///   - capturedOutput: The last N lines of terminal output from `capture-pane`.
    ///   - now: Current time as Unix timestamp (seconds since epoch).
    /// - Returns: Aggregated `PaneState`.
    public static func detect(
        pane: TmuxPane,
        capturedOutput: String,
        now: TimeInterval
    ) -> PaneState {
        let command = pane.currentCommand
        let isShell = isShellProcess(command)
        let isRunning = !isShell && command != nil
        let isLongRunning = isRunning
            && pane.startTime.map({ now - $0 > longRunningThreshold }) ?? false
        let agentState = detectAgentState(
            capturedOutput: capturedOutput,
            isRunning: isRunning
        )
        let exitCode = parseExitCode(from: capturedOutput)

        return PaneState(
            command: command,
            isRunning: isRunning,
            isLongRunning: isLongRunning,
            detectedAgentState: agentState,
            exitCode: exitCode
        )
    }

    // MARK: - Private

    /// Check if the command is a shell process (idle pane).
    static func isShellProcess(_ command: String?) -> Bool {
        guard let command, !command.isEmpty else { return true }
        return shellCommands.contains(command)
    }

    /// Detect agent state from captured output using pattern matching.
    /// Checks the last few lines of output for known patterns.
    static func detectAgentState(
        capturedOutput: String,
        isRunning: Bool
    ) -> DetectedAgentState {
        let lines = capturedOutput
            .split(separator: "\n", omittingEmptySubsequences: false)
            .suffix(10)
            .map { String($0) }

        // Check patterns in priority order (highest first)
        if matchesWaitingForInput(lines) {
            return .waitingForInput
        }
        if matchesError(lines) {
            return .error
        }
        if matchesCompleted(lines) {
            return .completed
        }
        if isRunning {
            return .running
        }
        return .none
    }

    /// Match waiting-for-input patterns in captured output lines.
    static func matchesWaitingForInput(_ lines: [String]) -> Bool {
        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasSuffix("> ") || trimmed.hasSuffix("? ") { return true }
            let lower = trimmed.lowercased()
            if lower.contains("waiting for input") { return true }
            if lower.contains("[y/n]") { return true }
            if lower.contains("press any key") { return true }
            // Only check the last non-empty line for prompt patterns
            break
        }
        return false
    }

    /// Match error patterns in captured output lines.
    static func matchesError(_ lines: [String]) -> Bool {
        for line in lines {
            let lower = line.lowercased()
            if lower.contains("error:") { return true }
            if line.contains("FAILED") { return true }
            if lower.contains("panic:") { return true }
            if lower.contains("fatal:") { return true }
        }
        return false
    }

    /// Match completed patterns in captured output lines.
    /// Only checks the last few lines (near end of output).
    static func matchesCompleted(_ lines: [String]) -> Bool {
        let tail = lines.suffix(5)
        for line in tail {
            let lower = line.lowercased()
            if lower.contains("done") { return true }
            if lower.contains("complete") { return true }
            if lower.contains("finished") { return true }
        }
        return false
    }

    /// Best-effort exit code parsing from captured output.
    static func parseExitCode(from output: String) -> Int? {
        let lines = output.split(separator: "\n").suffix(10)
        for line in lines.reversed() {
            let lower = line.lowercased()
            // Match patterns like "exit code: 1", "exited with 1", "exit status: 1"
            if let code = extractExitCode(from: String(lower)) {
                return code
            }
        }
        return nil
    }

    /// Extract an exit code integer from a line matching known patterns.
    private static func extractExitCode(from line: String) -> Int? {
        let patterns = [
            "exit code: ", "exit code ", "exited with ",
            "exit status: ", "exit status ",
        ]
        for pattern in patterns {
            if let range = line.range(of: pattern) {
                let after = line[range.upperBound...]
                let digits = after.prefix(while: { $0.isNumber })
                if let code = Int(digits) {
                    return code
                }
            }
        }
        return nil
    }
}
