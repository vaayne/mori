import Foundation

/// A single parsed line from tmux control-mode output.
///
/// The parser produces one `TmuxControlLine` per newline-terminated line.
/// Lines starting with `%` are control messages; all others are `.plainLine`
/// (response text within a `%begin/%end` block — block tracking is the
/// client's responsibility, not the parser's).
public enum TmuxControlLine: Sendable {
    /// Pane output with decoded bytes. Octal escapes have been unescaped.
    case output(paneId: String, data: Data)

    /// Start of a command response block.
    case begin(timestamp: Int, commandNumber: Int, flags: Int)

    /// Successful end of a command response block.
    case end(timestamp: Int, commandNumber: Int, flags: Int)

    /// Error end of a command response block.
    case error(timestamp: Int, commandNumber: Int, flags: Int)

    /// Asynchronous notification from the tmux server.
    case notification(TmuxNotification)

    /// Non-`%` line — response text within a `%begin/%end` block.
    /// Block tracking is the client's job, not the parser's.
    case plainLine(String)
}
