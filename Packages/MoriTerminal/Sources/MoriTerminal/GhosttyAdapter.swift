import AppKit
import MoriCore
import GhosttyKit

/// Terminal adapter backed by libghostty — GPU-accelerated terminal with
/// native mouse, scroll, paste, and IME support.
@MainActor
public final class GhosttyAdapter: TerminalHost {

    public var settings: TerminalSettings {
        didSet {
            if settings != oldValue {
                settings.save()
            }
        }
    }

    /// Maps NSView → ghostty_surface_t for lifecycle management.
    private var surfaces: [ObjectIdentifier: ghostty_surface_t] = [:]

    public init(settings: TerminalSettings = .load()) {
        self.settings = settings
        GhosttyApp.shared.start(settings: settings)
    }

    public func createSurface(command: String, workingDirectory: String) -> NSView {
        guard let app = GhosttyApp.shared.app else {
            NSLog("[GhosttyAdapter] GhosttyApp not initialized, falling back to empty view")
            return NSView()
        }

        let surfaceView = GhosttySurfaceView(frame: .zero)

        // Wrap command in a login shell so PATH includes mise-installed tools.
        // Ghostty's default execution uses /bin/bash --noprofile --norc which
        // skips profile loading, making tools like tmux unavailable.
        let shellCommand = "/bin/zsh -l -c " + shellEscape(command)
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
        config.font_size = Float(settings.fontSize)
        config.context = GHOSTTY_SURFACE_CONTEXT_WINDOW
        config.wait_after_command = false
        config.command = UnsafePointer(cCommand)
        config.working_directory = UnsafePointer(cWorkDir)

        // Build env vars for tmux compatibility
        let envKeyStrs = ["TERM", "LANG", "HOME"]
        let envValueStrs = ["xterm-256color", "en_US.UTF-8", NSHomeDirectory()]
        let envKeys = envKeyStrs.map { strdup($0) }
        let envValues = envValueStrs.map { strdup($0) }
        defer {
            envKeys.forEach { free($0) }
            envValues.forEach { free($0) }
        }

        var envVarArray = (0..<envKeys.count).map { i in
            ghostty_env_var_s(key: UnsafePointer(envKeys[i]!), value: UnsafePointer(envValues[i]!))
        }

        let surface: ghostty_surface_t? = envVarArray.withUnsafeMutableBufferPointer { buffer in
            config.env_vars = buffer.baseAddress
            config.env_var_count = envKeys.count
            return ghostty_surface_new(app, &config)
        }

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

    public func applySettings(to surface: NSView) {
        guard let surfaceView = surface as? GhosttySurfaceView,
              let ghosttySurface = surfaceView.ghosttySurface
        else { return }

        // Hot-reload config on the live surface
        GhosttyApp.shared.updateSurfaceConfig(surface: ghosttySurface, settings: settings)
    }

    // MARK: - Private

    private func shellEscape(_ str: String) -> String {
        "'" + str.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
