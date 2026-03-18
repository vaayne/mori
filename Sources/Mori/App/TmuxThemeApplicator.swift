import MoriCore
import MoriTmux

/// Applies terminal theme colors to tmux so that tmux's own rendering
/// (pane background, status bar, borders) matches the selected theme.
///
/// Uses `set-option -g` for global defaults — all sessions inherit these.
/// Then refreshes every connected client so changes take effect immediately.
///
/// TODO: Live theme application does not work yet. The tmux set-option and
/// refresh-client commands execute without error, but the visible terminal
/// does not update. Possible causes:
/// - SwiftTerm's embedded tmux client may not respond to external refresh-client
/// - tmux may require the client to redraw via the PTY (not just server-side refresh)
/// - May need to send an escape sequence or resize event through the PTY to force repaint
/// Settings ARE persisted and applied correctly on next surface creation (new session/restart).
enum TmuxThemeApplicator {

    static func apply(settings: TerminalSettings, tmuxBackend: TmuxBackend) async {
        let theme = settings.theme
        let fg = hexColor(theme.foreground)
        let bg = hexColor(theme.background)

        let windowStyle = "fg=\(fg),bg=\(bg)"
        let borderFg = hexColor(theme.ansi[8])      // bright black
        let activeBorderFg = hexColor(theme.ansi[4]) // blue
        let statusBg = hexColor(theme.ansi[0])       // palette black

        let options: [(String, String)] = [
            ("window-style", windowStyle),
            ("window-active-style", windowStyle),
            ("pane-border-style", "fg=\(borderFg)"),
            ("pane-active-border-style", "fg=\(activeBorderFg)"),
            ("status-style", "fg=\(fg),bg=\(statusBg)"),
            ("message-style", "fg=\(fg),bg=\(statusBg)"),
        ]

        for (option, value) in options {
            try? await tmuxBackend.setOption(sessionId: nil, option: option, value: value)
        }

        // Force all attached clients to redraw
        try? await tmuxBackend.refreshClients()
    }

    private static func hexColor(_ hex: String) -> String {
        let stripped = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        return "#\(stripped)"
    }
}
