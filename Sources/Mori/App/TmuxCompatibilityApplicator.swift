import MoriTmux

/// Applies tmux runtime compatibility settings Mori depends on regardless of the
/// user's onboarding preset preference.
enum TmuxCompatibilityApplicator {
    static func apply(tmuxBackend: TmuxBackend) async {
        // Global compatibility for image protocols in tmux (affects all sessions,
        // including non-Mori sessions attached from remote hosts).
        try? await tmuxBackend.setOption(sessionId: nil, option: "allow-passthrough", value: "on")
        await ensureGlobalUpdateEnvironment(tmuxBackend: tmuxBackend)

        // Help terminal-aware apps (e.g. Yazi) detect Ghostty capabilities,
        // especially across SSH+tmux where TERM_PROGRAM may be missing.
        try? await tmuxBackend.setEnvironment(name: "TERM_PROGRAM", value: "ghostty")

        do {
            let sessions = try await tmuxBackend.scanAll()
            for session in sessions where session.isMoriSession {
                try? await tmuxBackend.setOption(sessionId: session.id, option: "allow-passthrough", value: "on")
            }
        } catch {
            print("[TmuxCompatibilityApplicator] Failed to list sessions for compatibility options: \(error)")
        }
    }

    private static func ensureGlobalUpdateEnvironment(tmuxBackend: TmuxBackend) async {
        // Yazi image preview in tmux requires TERM/TERM_PROGRAM to be
        // propagated from the attached client environment.
        let updateEnv = (try? await tmuxBackend.globalOptionValues(option: "update-environment")) ?? []

        if !updateEnv.contains("TERM") {
            try? await tmuxBackend.appendOptionValue(
                sessionId: nil,
                option: "update-environment",
                value: "TERM"
            )
        }

        if !updateEnv.contains("TERM_PROGRAM") {
            try? await tmuxBackend.appendOptionValue(
                sessionId: nil,
                option: "update-environment",
                value: "TERM_PROGRAM"
            )
        }
    }
}
