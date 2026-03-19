import AppKit
import MoriCore
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

    private init() {}

    /// Initialize the ghostty runtime and create the app context.
    /// Call once before creating any surfaces.
    func start(settings: TerminalSettings) {
        guard !initialized else { return }
        initialized = true

        // Initialize the ghostty runtime
        guard ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) == GHOSTTY_SUCCESS else {
            NSLog("[GhosttyApp] ghostty_init failed")
            return
        }

        // Build config from settings
        guard let config = buildConfig(settings: settings) else {
            NSLog("[GhosttyApp] failed to create config")
            return
        }

        // Build runtime config with callbacks
        var runtimeConfig = ghostty_runtime_config_s(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
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

    /// Build a ghostty config from TerminalSettings.
    func buildConfig(settings: TerminalSettings) -> ghostty_config_t? {
        guard let config = ghostty_config_new() else { return nil }

        // Write settings to a temp config file and load it
        let path = GhosttyConfigWriter.write(settings: settings)
        ghostty_config_load_file(config, path)
        ghostty_config_finalize(config)

        return config
    }

    /// Update the app-level config (affects new surfaces).
    func updateConfig(settings: TerminalSettings) {
        guard let app else { return }
        guard let config = buildConfig(settings: settings) else { return }
        ghostty_app_update_config(app, config)
        ghostty_config_free(config)
    }

    /// Update config for a specific surface (hot-reload).
    func updateSurfaceConfig(surface: ghostty_surface_t, settings: TerminalSettings) {
        guard let config = buildConfig(settings: settings) else { return }
        ghostty_surface_update_config(surface, config)
        ghostty_config_free(config)
    }

    // MARK: - Event Loop

    func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
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
