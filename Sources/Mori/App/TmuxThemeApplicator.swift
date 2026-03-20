import MoriTerminal
import MoriTmux

/// Applies ghostty theme colors to tmux so that tmux's own rendering
/// (pane background, status bar, borders) matches the terminal theme.
///
/// Reads resolved colors from GhosttyThemeInfo (extracted from ghostty's config)
/// and sets both global defaults (for new sessions) and per-session overrides.
enum TmuxThemeApplicator {

    static func apply(themeInfo: GhosttyThemeInfo, tmuxBackend: TmuxBackend) async {
        let fg = GhosttyThemeInfo.hexString(themeInfo.foreground)
        let bg = GhosttyThemeInfo.hexString(themeInfo.background)

        let windowStyle = "fg=\(fg),bg=\(bg)"
        let borderFg = themeInfo.palette.count > 8
            ? GhosttyThemeInfo.hexString(themeInfo.palette[8])  // bright black
            : fg
        let activeBorderFg = themeInfo.palette.count > 4
            ? GhosttyThemeInfo.hexString(themeInfo.palette[4])  // blue
            : fg
        let statusBg = themeInfo.palette.count > 0
            ? GhosttyThemeInfo.hexString(themeInfo.palette[0])  // palette black
            : bg

        // Session-level options (set-option -g)
        let sessionOptions: [(String, String)] = [
            ("mouse", "on"),
            ("status", "off"),
            ("status-style", "fg=\(fg),bg=\(statusBg)"),
            ("message-style", "fg=\(fg),bg=\(statusBg)"),
        ]

        // Window-level options (set-option -gw)
        let windowOptions: [(String, String)] = [
            ("window-style", windowStyle),
            ("window-active-style", windowStyle),
            ("pane-border-style", "fg=\(borderFg)"),
            ("pane-active-border-style", "fg=\(activeBorderFg)"),
        ]

        // Apply only to Mori-managed sessions (those matching <project>/<branch> naming).
        // Non-Mori sessions are left untouched so they inherit the user's tmux.conf.
        do {
            let sessions = try await tmuxBackend.scanAll()
            for session in sessions where session.isMoriSession {
                for (option, value) in sessionOptions {
                    try? await tmuxBackend.setOption(sessionId: session.id, option: option, value: value)
                }
                for (option, value) in windowOptions {
                    try? await tmuxBackend.setWindowOption(global: false, target: session.id, option: option, value: value)
                }
            }
        } catch {
            print("[TmuxThemeApplicator] Failed to list sessions for per-session theme: \(error)")
        }

        // Force all attached clients to redraw
        do {
            try await tmuxBackend.refreshClients()
        } catch {
            print("[TmuxThemeApplicator] Failed to refresh clients: \(error)")
        }
    }
}
