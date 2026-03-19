import AppKit
import GhosttyKit

/// Sendable wrapper for raw pointers crossing isolation boundaries in C callbacks.
private struct SendableRawPointer: @unchecked Sendable {
    let pointer: UnsafeMutableRawPointer
}

/// Sendable wrapper for const C string pointers.
private struct SendableCString: @unchecked Sendable {
    let pointer: UnsafePointer<CChar>
}

/// Singleton managing the ghostty application context.
/// Owns the `ghostty_app_t` instance, runtime callbacks, and event loop tick scheduling.
/// Created once and shared by all GhosttyAdapter surfaces.
@MainActor
final class GhosttyApp {

    static let shared = GhosttyApp()

    private(set) var app: ghostty_app_t?
    private var initialized = false

    /// Theme colors resolved from the ghostty config at startup.
    private(set) var themeInfo: GhosttyThemeInfo = .fallback

    private init() {}

    /// Initialize the ghostty runtime and create the app context.
    /// Call once before creating any surfaces.
    func start() {
        guard !initialized else { return }
        initialized = true

        // Initialize the ghostty runtime
        guard ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) == GHOSTTY_SUCCESS else {
            NSLog("[GhosttyApp] ghostty_init failed")
            return
        }

        // Build config: user's ghostty config + Mori overrides
        guard let config = buildConfig() else {
            NSLog("[GhosttyApp] failed to create config")
            return
        }

        // Extract theme info before the config is consumed by ghostty_app_new
        self.themeInfo = GhosttyThemeInfo.from(config: config)

        // Build runtime config in nonisolated context so closures don't
        // inherit @MainActor isolation (they're called from renderer thread).
        let userdata = Unmanaged.passUnretained(self).toOpaque()
        var runtimeConfig = Self.makeRuntimeConfig(userdata: userdata)

        guard let app = ghostty_app_new(&runtimeConfig, config) else {
            NSLog("[GhosttyApp] ghostty_app_new failed")
            ghostty_config_free(config)
            return
        }

        self.app = app
        ghostty_config_free(config)

        // Set initial focus state
        ghostty_app_set_focus(app, NSApp.isActive)
    }

    // Singleton lives for app lifetime — no deinit needed.
    // ghostty_app_free would be called here if this weren't a singleton.

    // MARK: - Surface Registry

    /// Maps userdata pointers to ghostty surfaces for clipboard callbacks.
    private var surfaceRegistry: [UnsafeMutableRawPointer: ghostty_surface_t] = [:]

    func registerSurface(_ surface: ghostty_surface_t, userdata: UnsafeMutableRawPointer) {
        surfaceRegistry[userdata] = surface
    }

    func unregisterSurface(userdata: UnsafeMutableRawPointer) {
        surfaceRegistry.removeValue(forKey: userdata)
    }

    func surfaceFromUserdata(_ userdata: UnsafeMutableRawPointer) -> ghostty_surface_t? {
        surfaceRegistry[userdata]
    }

    // MARK: - Config

    /// Build a ghostty config: load user's config first, then apply Mori overrides.
    func buildConfig() -> ghostty_config_t? {
        guard let config = ghostty_config_new() else { return nil }

        // 1. Load user's ghostty config (standard path)
        let userConfig = NSHomeDirectory() + "/.config/ghostty/config"
        if FileManager.default.fileExists(atPath: userConfig) {
            ghostty_config_load_file(config, userConfig)
        }

        // 2. Apply Mori embedding overrides (window-decoration, etc.)
        let overridePath = GhosttyConfigWriter.write()
        ghostty_config_load_file(config, overridePath)

        ghostty_config_finalize(config)
        return config
    }

    /// Reload config from disk and update the running app + extract new theme.
    /// Call after writing changes to ~/.config/ghostty/config.
    func reloadConfig() {
        guard let app else { return }
        guard let config = buildConfig() else { return }
        self.themeInfo = GhosttyThemeInfo.from(config: config)
        ghostty_app_update_config(app, config)
        ghostty_config_free(config)
    }

    // MARK: - Event Loop

    func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    // MARK: - Runtime Config Factory

    /// Build runtime config in a nonisolated context. This is critical because
    /// ghostty calls these callbacks from its renderer/IO threads, and closures
    /// created inside @MainActor methods inherit that isolation, causing
    /// dispatch_assert_queue_fail crashes.
    private nonisolated static func makeRuntimeConfig(
        userdata: UnsafeMutableRawPointer
    ) -> ghostty_runtime_config_s {
        ghostty_runtime_config_s(
            userdata: userdata,
            supports_selection_clipboard: false,
            wakeup_cb: { userdata in GhosttyApp.onWakeup(userdata) },
            action_cb: { app, target, action in GhosttyApp.onAction(app, target: target, action: action) },
            read_clipboard_cb: { userdata, loc, state in GhosttyApp.onReadClipboard(userdata, location: loc, state: state) },
            confirm_read_clipboard_cb: { userdata, str, state, request in
                GhosttyApp.onConfirmReadClipboard(userdata, string: str, state: state, request: request)
            },
            write_clipboard_cb: { userdata, loc, content, len, confirm in
                GhosttyApp.onWriteClipboard(userdata, location: loc, content: content, len: len, confirm: confirm)
            },
            close_surface_cb: { userdata, processAlive in
                GhosttyApp.onCloseSurface(userdata, processAlive: processAlive)
            }
        )
    }

    // MARK: - Runtime Callbacks (static, called from C)

    private nonisolated static func onWakeup(_ userdata: UnsafeMutableRawPointer?) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                GhosttyApp.shared.tick()
            }
        }
    }

    private nonisolated static func onAction(
        _ app: ghostty_app_t?,
        target: ghostty_target_s,
        action: ghostty_action_s
    ) -> Bool {
        return false
    }

    private nonisolated static func onReadClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        state: UnsafeMutableRawPointer?
    ) -> Bool {
        guard let userdata, let state else { return false }
        let ud = SendableRawPointer(pointer: userdata)
        let st = SendableRawPointer(pointer: state)

        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let pasteboard = NSPasteboard.general
                guard let str = pasteboard.string(forType: .string) else { return }
                guard let surface = GhosttyApp.shared.surfaceFromUserdata(ud.pointer) else { return }
                str.withCString { ptr in
                    ghostty_surface_complete_clipboard_request(surface, ptr, st.pointer, false)
                }
            }
        }
        return true
    }

    private nonisolated static func onConfirmReadClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        string: UnsafePointer<CChar>?,
        state: UnsafeMutableRawPointer?,
        request: ghostty_clipboard_request_e
    ) {
        guard let userdata, let string, let state else { return }
        let ud = SendableRawPointer(pointer: userdata)
        let str = SendableCString(pointer: string)
        let st = SendableRawPointer(pointer: state)

        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard let surface = GhosttyApp.shared.surfaceFromUserdata(ud.pointer) else { return }
                ghostty_surface_complete_clipboard_request(surface, str.pointer, st.pointer, true)
            }
        }
    }

    private nonisolated static func onWriteClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        content: UnsafePointer<ghostty_clipboard_content_s>?,
        len: Int,
        confirm: Bool
    ) {
        guard let content, len > 0 else { return }

        // Extract clipboard content on the calling thread (pointers may not survive dispatch)
        var textContent: String?
        for i in 0..<len {
            let item = content[i]
            guard let mime = item.mime, let data = item.data else { continue }
            if String(cString: mime) == "text/plain" {
                textContent = String(cString: data)
                break
            }
        }

        guard let text = textContent else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            }
        }
    }

    private nonisolated static func onCloseSurface(
        _ userdata: UnsafeMutableRawPointer?,
        processAlive: Bool
    ) {
        // Surface close requested by ghostty (e.g., shell exited).
    }
}
