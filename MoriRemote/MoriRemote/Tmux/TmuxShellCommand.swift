import Foundation

/// Foundation-only POSIX command assembly. It is kept free of app types so the host
/// contract test can compile and execute the exact production implementation.
enum TmuxShellCommand {
    static let fallbackPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    static func command(executable: String, arguments: [String]) -> String {
        let executableToken = quote(executable)
        let argumentTokens = arguments.map(quote).joined(separator: " ")
        return "PATH=\(quote(fallbackPath)):$PATH; export PATH; tmux_path=$(command -v -- \(executableToken)) || exit 127; exec \"$tmux_path\" \(argumentTokens)"
    }

    /// In POSIX shell, a single quote inside a single-quoted word must close the
    /// word, emit a quoted apostrophe, then reopen it: `'"'"'`.
    static func quote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}
