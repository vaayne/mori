import MoriCore
import MoriTerminal
import MoriTmux

/// Orchestrates Mori's tmux configuration layers:
/// 1. runtime compatibility required by Mori
/// 2. optional onboarding defaults for Mori-managed sessions
/// 3. theme synchronization with Ghostty colors
enum TmuxConfigurationApplicator {
    static func apply(
        themeInfo: GhosttyThemeInfo,
        toolSettings: ToolSettings,
        tmuxBackend: TmuxBackend,
        forceTheme: Bool = false
    ) async {
        await TmuxCompatibilityApplicator.apply(tmuxBackend: tmuxBackend)
        await TmuxPresetApplicator.apply(
            enabled: toolSettings.applyMoriTmuxDefaults,
            tmuxBackend: tmuxBackend
        )
        await TmuxThemeApplicator.apply(
            themeInfo: themeInfo,
            tmuxBackend: tmuxBackend,
            force: forceTheme
        )

        do {
            try await tmuxBackend.refreshClients()
        } catch {
            print("[TmuxConfigurationApplicator] Failed to refresh clients: \(error)")
        }
    }
}
