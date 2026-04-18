import MoriTerminal
import MoriTmux

/// Applies Ghostty theme colors to tmux so that tmux's own rendering
/// (pane background, status bar, borders) matches the terminal theme.
///
/// Only Mori-managed sessions are themed. Runtime compatibility defaults and
/// onboarding presets are handled by separate applicators.
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
        private var lastAppliedPayloads: [ObjectIdentifier: ThemePayload] = [:]

        func shouldApply(_ payload: ThemePayload, backendID: ObjectIdentifier) -> Bool {
            payload != lastAppliedPayloads[backendID]
        }

        func markApplied(_ payload: ThemePayload, backendID: ObjectIdentifier) {
            lastAppliedPayloads[backendID] = payload
        }
    }

    private static let cache = Cache()

    static func apply(themeInfo: GhosttyThemeInfo, tmuxBackend: TmuxBackend, force: Bool = false) async {
        let payload = makePayload(themeInfo: themeInfo)
        let backendID = ObjectIdentifier(tmuxBackend)
        if !force {
            guard await cache.shouldApply(payload, backendID: backendID) else { return }
        }

        let styles = makeStyles(payload: payload)
        await applySessionThemes(styles: styles, tmuxBackend: tmuxBackend)
        await cache.markApplied(payload, backendID: backendID)
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
            ("status-style", "fg=\(fg),bg=\(statusBackground)"),
            ("message-style", "fg=\(fg),bg=\(statusBackground)"),
        ]

        let windowOptions: [(String, String)] = [
            ("window-style", "fg=\(fg),bg=\(windowBackground)"),
            ("window-active-style", "fg=\(fg),bg=\(windowBackground)"),
            ("pane-border-style", "fg=\(borderFg)"),
            ("pane-active-border-style", "fg=\(activeBorderFg)"),
        ]

        return ThemeStyles(sessionOptions: sessionOptions, windowOptions: windowOptions)
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

                for (option, value) in styles.windowOptions {
                    try? await tmuxBackend.setWindowOption(global: false, target: session.id, option: option, value: value)
                }
            }
        } catch {
            print("[TmuxThemeApplicator] Failed to list sessions for per-session theme: \(error)")
        }
    }

    private static func paletteColor(_ palette: [String], index: Int, fallback: String) -> String {
        guard palette.indices.contains(index) else { return fallback }
        return palette[index]
    }
}
