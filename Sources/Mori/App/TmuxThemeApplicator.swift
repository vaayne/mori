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

        let defaultBackedWindowStyle = themeInfo.backgroundOpacity < 1 && !themeInfo.backgroundOpacityCells
        let windowStyle = defaultBackedWindowStyle ? "fg=\(fg),bg=default" : "fg=\(fg),bg=\(bg)"
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
        let statusStyle = defaultBackedWindowStyle ? "fg=\(fg),bg=default" : "fg=\(fg),bg=\(statusBg)"
        let sessionOptions: [(String, String)] = [
            ("mouse", "on"),
            ("status", "off"),
            ("status-style", statusStyle),
            ("message-style", statusStyle),
            ("allow-passthrough", "on"),
        ]

        // Window-level options (set-option -gw)
        let windowOptions: [(String, String)] = [
            ("window-style", windowStyle),
            ("window-active-style", windowStyle),
            ("pane-border-style", "fg=\(borderFg)"),
            ("pane-active-border-style", "fg=\(activeBorderFg)"),
        ]

        // Global compatibility for image protocols in tmux (affects all sessions,
        // including non-Mori sessions attached from remote hosts).
        try? await tmuxBackend.setOption(sessionId: nil, option: "allow-passthrough", value: "on")
        let globalUpdateEnv = (try? await tmuxBackend.optionValues(
            sessionId: nil,
            option: "update-environment"
        )) ?? []
        if !globalUpdateEnv.contains("TERM") {
            try? await tmuxBackend.appendOptionValue(
                sessionId: nil,
                option: "update-environment",
                value: "TERM"
            )
        }
        if !globalUpdateEnv.contains("TERM_PROGRAM") {
            try? await tmuxBackend.appendOptionValue(
                sessionId: nil,
                option: "update-environment",
                value: "TERM_PROGRAM"
            )
        }

        // Apply only to Mori-managed sessions (those matching <project>/<branch> naming).
        // Non-Mori sessions are left untouched so they inherit the user's tmux.conf.
        do {
            let sessions = try await tmuxBackend.scanAll()
            for session in sessions where session.isMoriSession {
                for (option, value) in sessionOptions {
                    try? await tmuxBackend.setOption(sessionId: session.id, option: option, value: value)
                }

                // Yazi image preview in tmux requires TERM/TERM_PROGRAM to be
                // propagated from the attached client environment.
                let updateEnv = (try? await tmuxBackend.optionValues(
                    sessionId: session.id,
                    option: "update-environment"
                )) ?? []
                if !updateEnv.contains("TERM") {
                    try? await tmuxBackend.appendOptionValue(
                        sessionId: session.id,
                        option: "update-environment",
                        value: "TERM"
                    )
                }
                if !updateEnv.contains("TERM_PROGRAM") {
                    try? await tmuxBackend.appendOptionValue(
                        sessionId: session.id,
                        option: "update-environment",
                        value: "TERM_PROGRAM"
                    )
                }

                for (option, value) in windowOptions {
                    try? await tmuxBackend.setWindowOption(global: false, target: session.id, option: option, value: value)
                }
            }
        } catch {
            print("[TmuxThemeApplicator] Failed to list sessions for per-session theme: \(error)")
        }

        // Help terminal-aware apps (e.g. Yazi) detect Ghostty capabilities,
        // especially across SSH+tmux where TERM_PROGRAM may be missing.
        try? await tmuxBackend.setEnvironment(name: "TERM_PROGRAM", value: "ghostty")

        // Force all attached clients to redraw
        do {
            try await tmuxBackend.refreshClients()
        } catch {
            print("[TmuxThemeApplicator] Failed to refresh clients: \(error)")
        }
    }
}
