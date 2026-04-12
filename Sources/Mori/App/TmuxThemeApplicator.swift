import MoriTerminal
import MoriTmux

/// Applies ghostty theme colors to tmux so that tmux's own rendering
/// (pane background, status bar, borders) matches the terminal theme.
///
/// Reads resolved colors from GhosttyThemeInfo (extracted from ghostty's config)
/// and sets both global defaults (for new sessions) and per-session overrides.
enum TmuxThemeApplicator {
    private struct ThemePayload: Equatable {
        let foreground: String
        let background: String
        let prefersDefaultBackgrounds: Bool
        let palette: [String]
    }

    private struct ThemeStyles {
        let sessionOptions: [(String, String)]
        let windowOptions: [(String, String)]
    }

    private actor Cache {
        private var lastAppliedPayload: ThemePayload?

        func shouldApply(_ payload: ThemePayload) -> Bool {
            payload != lastAppliedPayload
        }

        func markApplied(_ payload: ThemePayload) {
            lastAppliedPayload = payload
        }
    }

    private static let cache = Cache()

    static func apply(themeInfo: GhosttyThemeInfo, tmuxBackend: TmuxBackend) async {
        let payload = makePayload(themeInfo: themeInfo)
        guard await cache.shouldApply(payload) else { return }

        let styles = makeStyles(payload: payload)
        await applyGlobalCompatibilityOptions(tmuxBackend: tmuxBackend)
        await applySessionThemes(styles: styles, tmuxBackend: tmuxBackend)

        // Help terminal-aware apps (e.g. Yazi) detect Ghostty capabilities,
        // especially across SSH+tmux where TERM_PROGRAM may be missing.
        try? await tmuxBackend.setEnvironment(name: "TERM_PROGRAM", value: "ghostty")

        do {
            try await tmuxBackend.refreshClients()
            await cache.markApplied(payload)
        } catch {
            print("[TmuxThemeApplicator] Failed to refresh clients: \(error)")
        }
    }

    private static func makePayload(themeInfo: GhosttyThemeInfo) -> ThemePayload {
        ThemePayload(
            foreground: GhosttyThemeInfo.hexString(themeInfo.foreground),
            background: GhosttyThemeInfo.hexString(themeInfo.background),
            prefersDefaultBackgrounds: themeInfo.backgroundOpacity < 1 && !themeInfo.backgroundOpacityCells,
            palette: themeInfo.palette.map(GhosttyThemeInfo.hexString)
        )
    }

    private static func makeStyles(payload: ThemePayload) -> ThemeStyles {
        let fg = payload.foreground
        let bg = payload.background
        let windowBackground = payload.prefersDefaultBackgrounds ? "default" : bg
        let statusBackground = payload.prefersDefaultBackgrounds
            ? "default"
            : paletteColor(payload.palette, index: 0, fallback: bg)
        let borderFg = paletteColor(payload.palette, index: 8, fallback: fg)
        let activeBorderFg = paletteColor(payload.palette, index: 4, fallback: fg)

        let sessionOptions: [(String, String)] = [
            ("mouse", "on"),
            ("status", "off"),
            ("status-style", "fg=\(fg),bg=\(statusBackground)"),
            ("message-style", "fg=\(fg),bg=\(statusBackground)"),
            ("allow-passthrough", "on"),
        ]

        let windowOptions: [(String, String)] = [
            ("window-style", "fg=\(fg),bg=\(windowBackground)"),
            ("window-active-style", "fg=\(fg),bg=\(windowBackground)"),
            ("pane-border-style", "fg=\(borderFg)"),
            ("pane-active-border-style", "fg=\(activeBorderFg)"),
        ]

        return ThemeStyles(sessionOptions: sessionOptions, windowOptions: windowOptions)
    }

    private static func applyGlobalCompatibilityOptions(tmuxBackend: TmuxBackend) async {
        // Global compatibility for image protocols in tmux (affects all sessions,
        // including non-Mori sessions attached from remote hosts).
        try? await tmuxBackend.setOption(sessionId: nil, option: "allow-passthrough", value: "on")
        await ensureUpdateEnvironment(sessionId: nil, tmuxBackend: tmuxBackend)
    }

    private static func applySessionThemes(styles: ThemeStyles, tmuxBackend: TmuxBackend) async {
        // Apply only to Mori-managed sessions (those matching <project>/<branch> naming).
        // Non-Mori sessions are left untouched so they inherit the user's tmux.conf.
        do {
            let sessions = try await tmuxBackend.scanAll()
            for session in sessions where session.isMoriSession {
                for (option, value) in styles.sessionOptions {
                    try? await tmuxBackend.setOption(sessionId: session.id, option: option, value: value)
                }

                await ensureUpdateEnvironment(sessionId: session.id, tmuxBackend: tmuxBackend)

                for (option, value) in styles.windowOptions {
                    try? await tmuxBackend.setWindowOption(global: false, target: session.id, option: option, value: value)
                }
            }
        } catch {
            print("[TmuxThemeApplicator] Failed to list sessions for per-session theme: \(error)")
        }
    }

    private static func ensureUpdateEnvironment(sessionId: String?, tmuxBackend: TmuxBackend) async {
        // Yazi image preview in tmux requires TERM/TERM_PROGRAM to be
        // propagated from the attached client environment.
        let updateEnv = (try? await tmuxBackend.optionValues(
            sessionId: sessionId,
            option: "update-environment"
        )) ?? []

        if !updateEnv.contains("TERM") {
            try? await tmuxBackend.appendOptionValue(
                sessionId: sessionId,
                option: "update-environment",
                value: "TERM"
            )
        }

        if !updateEnv.contains("TERM_PROGRAM") {
            try? await tmuxBackend.appendOptionValue(
                sessionId: sessionId,
                option: "update-environment",
                value: "TERM_PROGRAM"
            )
        }
    }

    private static func paletteColor(_ palette: [String], index: Int, fallback: String) -> String {
        guard palette.indices.contains(index) else { return fallback }
        return palette[index]
    }
}
