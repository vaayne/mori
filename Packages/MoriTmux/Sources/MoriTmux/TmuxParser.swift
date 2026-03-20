import Foundation

/// Parses structured output from tmux `-F` format strings.
///
/// Uses tab (`\t`) as a field delimiter in format strings to avoid collisions
/// with values that might contain colons, spaces, or other common characters.
public enum TmuxParser {

    /// The delimiter used between fields in tmux format strings.
    public static let delimiter = "\t"

    // MARK: - Format Strings

    /// Format string for `tmux list-sessions -F`.
    public static let sessionFormat: String = [
        "#{session_id}",
        "#{session_name}",
        "#{session_windows}",
        "#{session_attached}",
    ].joined(separator: delimiter)

    /// Format string for `tmux list-windows -F`.
    public static let windowFormat: String = [
        "#{window_id}",
        "#{window_index}",
        "#{window_name}",
        "#{window_active}",
        "#{pane_current_path}",
    ].joined(separator: delimiter)

    /// Format string for `tmux list-panes -F`.
    public static let paneFormat: String = [
        "#{pane_id}",
        "#{pane_tty}",
        "#{pane_active}",
        "#{pane_current_path}",
        "#{pane_title}",
        "#{pane_activity}",
        "#{pane_current_command}",
        "#{pane_start_time}",
        "#{pane_pid}",
        "#{@mori-agent-state}",
        "#{@mori-agent-name}",
    ].joined(separator: delimiter)

    // MARK: - Parsing

    /// Parse the output of `tmux list-sessions -F` into `TmuxSession` models.
    public static func parseSessions(_ output: String) -> [TmuxSession] {
        parseLines(output).compactMap { fields in
            guard fields.count >= 4 else { return nil }
            let sessionId = fields[0]
            let name = fields[1]
            let windowCount = Int(fields[2]) ?? 0
            let isAttached = fields[3] == "1"
            return TmuxSession(
                sessionId: sessionId,
                name: name,
                windowCount: windowCount,
                isAttached: isAttached
            )
        }
    }

    /// Parse the output of `tmux list-windows -F` into `TmuxWindow` models.
    public static func parseWindows(_ output: String) -> [TmuxWindow] {
        parseLines(output).compactMap { fields in
            guard fields.count >= 5 else { return nil }
            let windowId = fields[0]
            let windowIndex = Int(fields[1]) ?? 0
            let name = fields[2]
            let isActive = fields[3] == "1"
            let currentPath = fields[4].isEmpty ? nil : fields[4]
            return TmuxWindow(
                windowId: windowId,
                windowIndex: windowIndex,
                name: name,
                isActive: isActive,
                currentPath: currentPath
            )
        }
    }

    /// Parse the output of `tmux list-panes -F` into `TmuxPane` models.
    public static func parsePanes(_ output: String) -> [TmuxPane] {
        parseLines(output).compactMap { fields in
            guard fields.count >= 5 else { return nil }
            let paneId = fields[0]
            let tty = fields[1].isEmpty ? nil : fields[1]
            let isActive = fields[2] == "1"
            let currentPath = fields[3].isEmpty ? nil : fields[3]
            let title = fields[4].isEmpty ? nil : fields[4]
            let lastActivity: TimeInterval? = fields.count >= 6 ? Double(fields[5]) : nil
            let currentCommand: String? = fields.count >= 7 && !fields[6].isEmpty ? fields[6] : nil
            let startTime: TimeInterval? = fields.count >= 8 ? Double(fields[7]) : nil
            let pid: String? = fields.count >= 9 && !fields[8].isEmpty ? fields[8] : nil
            let agentState: String? = fields.count >= 10 && !fields[9].isEmpty ? fields[9] : nil
            let agentName: String? = fields.count >= 11 && !fields[10].isEmpty ? fields[10] : nil
            return TmuxPane(
                paneId: paneId,
                tty: tty,
                isActive: isActive,
                currentPath: currentPath,
                title: title,
                lastActivity: lastActivity,
                currentCommand: currentCommand,
                startTime: startTime,
                pid: pid,
                agentState: agentState,
                agentName: agentName
            )
        }
    }

    // MARK: - Private

    /// Split raw tmux output into lines, then split each line by the delimiter.
    private static func parseLines(_ output: String) -> [[String]] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line in
                String(line).components(separatedBy: delimiter)
            }
    }
}
