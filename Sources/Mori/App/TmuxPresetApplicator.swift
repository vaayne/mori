import MoriTmux

/// Applies Mori's onboarding-focused tmux defaults to Mori-managed sessions only.
enum TmuxPresetApplicator {
    private static let sessionOptions: [(String, String)] = [
        ("mouse", "on"),
        ("status", "off"),
    ]

    static func apply(enabled: Bool, tmuxBackend: TmuxBackend) async {
        do {
            let sessions = try await tmuxBackend.scanAll()
            for session in sessions where session.isMoriSession {
                if enabled {
                    await applySessionOptions(sessionId: session.id, tmuxBackend: tmuxBackend)
                } else {
                    await clearSessionOptions(sessionId: session.id, tmuxBackend: tmuxBackend)
                }
            }
        } catch {
            print("[TmuxPresetApplicator] Failed to list sessions for Mori preset application: \(error)")
        }
    }

    private static func applySessionOptions(sessionId: String, tmuxBackend: TmuxBackend) async {
        for (option, value) in sessionOptions {
            try? await tmuxBackend.setOption(sessionId: sessionId, option: option, value: value)
        }
    }

    private static func clearSessionOptions(sessionId: String, tmuxBackend: TmuxBackend) async {
        for (option, _) in sessionOptions {
            try? await tmuxBackend.unsetOption(sessionId: sessionId, option: option)
        }
    }
}
