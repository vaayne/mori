#if os(macOS)
import AppKit
import GhosttyKit

/// Terminal adapter backed by libghostty — GPU-accelerated terminal with
/// native mouse, scroll, paste, and IME support.
///
/// All user-facing configuration (font, theme, cursor, keybindings) comes from
/// Ghostty's own config at `~/.config/ghostty/config`. Mori only overrides
/// embedding-specific settings (window decoration, close confirmation).
@MainActor
public final class GhosttyAdapter: TerminalHost {

    /// Maps NSView → ghostty_surface_t for lifecycle management.
    private var surfaces: [ObjectIdentifier: ghostty_surface_t] = [:]

    /// Resolved theme colors from ghostty's config (background, foreground, palette).
    public var themeInfo: GhosttyThemeInfo { GhosttyApp.shared.themeInfo }

    public init() {
        GhosttyApp.shared.start()
    }

    /// Set a handler for ghostty keybinding actions (tabs, splits, etc.).
    /// Ghostty maps keys to abstract intents; the handler provides the
    /// implementation (e.g., tmux windows instead of ghostty-native tabs).
    public var actionHandler: (@MainActor (GhosttyAppAction) -> Void)? {
        get { GhosttyApp.shared.actionHandler }
        set { GhosttyApp.shared.actionHandler = newValue }
    }

    /// Reload ghostty config from disk and update all surfaces.
    /// Call after writing changes to ~/.config/ghostty/config.
    public func reloadConfig() {
        GhosttyApp.shared.reloadConfig()
    }

    /// Sync Ghostty's light/dark conditional theme branch to the current system appearance.
    public func setColorScheme(isDark: Bool) {
        GhosttyApp.shared.setColorScheme(isDark: isDark)
    }

    /// Apply Ghostty-derived window translucency and blur to the main workspace window.
    public func syncWorkspaceWindowAppearance(_ window: NSWindow) {
        applyWindowAppearance(window, allowsTransparency: true)
    }

    /// Apply Ghostty theme colors to a non-terminal window while keeping it opaque.
    public func syncThemedWindowAppearance(_ window: NSWindow) {
        applyWindowAppearance(window, allowsTransparency: false)
    }

    private func applyWindowAppearance(_ window: NSWindow, allowsTransparency: Bool) {
        let themeInfo = self.themeInfo
        window.appearance = NSAppearance(named: themeInfo.isDark ? .darkAqua : .aqua)

        let useTransparentBackground = allowsTransparency && !window.styleMask.contains(.fullScreen) && themeInfo.usesTransparentWindowBackground
        if useTransparentBackground {
            window.isOpaque = false
            window.backgroundColor = .white.withAlphaComponent(0.001)

            if window.isVisible,
               !themeInfo.backgroundBlur.isGlassStyle,
               let app = GhosttyApp.shared.app {
                ghostty_set_window_background_blur(app, Unmanaged.passUnretained(window).toOpaque())
            }
        } else {
            window.isOpaque = true
            window.backgroundColor = themeInfo.background.withAlphaComponent(1)
        }
    }

    public func createSurface(command: String, workingDirectory: String) -> NSView {
        guard let app = GhosttyApp.shared.app else {
            NSLog("[GhosttyAdapter] GhosttyApp not initialized, falling back to empty view")
            return NSView()
        }

        let surfaceView = GhosttySurfaceView(frame: .zero)

        // Wrap command in the user's login shell so PATH includes toolchain
        // managers (mise/nvm/pyenv/etc.). Keep this non-interactive to avoid
        // prompt init side effects (e.g. starship warnings) before tmux attaches.
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellCommand = shell + " -l -c " + shellEscape(command)
        let cCommand = strdup(shellCommand)
        let cWorkDir = strdup(workingDirectory)
        defer { free(cCommand); free(cWorkDir) }

        var config = ghostty_surface_config_new()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(
            macos: ghostty_platform_macos_s(nsview: Unmanaged.passUnretained(surfaceView).toOpaque())
        )
        config.userdata = Unmanaged.passUnretained(surfaceView).toOpaque()
        config.scale_factor = Double(NSScreen.main?.backingScaleFactor ?? 2.0)
        config.context = GHOSTTY_SURFACE_CONTEXT_WINDOW
        config.wait_after_command = false
        config.command = UnsafePointer(cCommand)
        config.working_directory = UnsafePointer(cWorkDir)

        let surface: ghostty_surface_t? = ghostty_surface_new(app, &config)

        guard let surface else {
            NSLog("[GhosttyAdapter] ghostty_surface_new failed")
            return surfaceView
        }

        surfaceView.ghosttySurface = surface
        surfaces[ObjectIdentifier(surfaceView)] = surface

        // Register in app's surface registry for clipboard callbacks
        let userdata = Unmanaged.passUnretained(surfaceView).toOpaque()
        GhosttyApp.shared.registerSurface(surface, userdata: userdata)

        return surfaceView
    }

    public func destroySurface(_ surface: NSView) {
        guard let surfaceView = surface as? GhosttySurfaceView,
              let ghosttySurface = surfaces.removeValue(forKey: ObjectIdentifier(surfaceView))
        else { return }

        // Unregister from clipboard callback registry
        let userdata = Unmanaged.passUnretained(surfaceView).toOpaque()
        GhosttyApp.shared.unregisterSurface(userdata: userdata)

        surfaceView.ghosttySurface = nil
        ghostty_surface_free(ghosttySurface)
    }

    public func surfaceDidResize(_ surface: NSView, to size: NSSize) {
        // GhosttySurfaceView handles resize in setFrameSize via ghostty_surface_set_size
    }

    public func focusSurface(_ surface: NSView) {
        surface.window?.makeFirstResponder(surface)
    }

    // MARK: - Private

    private func shellEscape(_ str: String) -> String {
        "'" + str.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
#endif
