#if os(iOS)
import Dispatch
import GhosttyKit
import UIKit

/// Minimal iOS ghostty host for the remote terminal spike.
@MainActor
public final class GhosttyiOSApp {

    public static let shared = GhosttyiOSApp()

    private(set) var app: ghostty_app_t?
    private var initialized = false

    private init() {}

    public func start() {
        guard !initialized else { return }
        initialized = true

        let cArg = strdup("mori-ios")
        defer { free(cArg) }
        var argvStorage: [UnsafeMutablePointer<CChar>?] = [cArg]

        let initResult = argvStorage.withUnsafeMutableBufferPointer { buffer -> Int32 in
            // ghostty_init expects (argc, char**) which imports as
            // UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
            ghostty_init(UInt(buffer.count), buffer.baseAddress!)
        }
        guard initResult == GHOSTTY_SUCCESS else {
            NSLog("[GhosttyiOSApp] ghostty_init failed")
            initialized = false
            return
        }

        guard let config = makeConfig() else {
            NSLog("[GhosttyiOSApp] failed to create config")
            initialized = false
            return
        }

        let userdata = Unmanaged.passUnretained(self).toOpaque()
        var runtimeConfig = Self.makeRuntimeConfig(userdata: userdata)
        guard let app = ghostty_app_new(&runtimeConfig, config) else {
            NSLog("[GhosttyiOSApp] ghostty_app_new failed")
            ghostty_config_free(config)
            initialized = false
            return
        }

        self.app = app
        ghostty_config_free(config)
    }

    public func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    public func createSurface(view: UIView, scaleFactor: Double) -> ghostty_surface_t? {
        start()
        guard let app else { return nil }

        var config = ghostty_surface_config_new()
        config.platform_tag = GHOSTTY_PLATFORM_IOS
        config.platform = ghostty_platform_u(
            ios: ghostty_platform_ios_s(uiview: Unmanaged.passUnretained(view).toOpaque())
        )
        config.userdata = Unmanaged.passUnretained(view).toOpaque()
        config.scale_factor = scaleFactor
        config.context = GHOSTTY_SURFACE_CONTEXT_WINDOW
        config.wait_after_command = false
        config.command = nil
        config.working_directory = nil

        return ghostty_surface_new(app, &config)
    }

    private func makeConfig() -> ghostty_config_t? {
        guard let config = ghostty_config_new() else { return nil }
        ghostty_config_finalize(config)
        return config
    }

    private nonisolated static func makeRuntimeConfig(
        userdata: UnsafeMutableRawPointer
    ) -> ghostty_runtime_config_s {
        ghostty_runtime_config_s(
            userdata: userdata,
            supports_selection_clipboard: false,
            wakeup_cb: { userdata in
                GhosttyiOSApp.onWakeup(userdata)
            },
            action_cb: { _, _, _ in false },
            read_clipboard_cb: { _, _, _ in false },
            confirm_read_clipboard_cb: { _, _, _, _ in },
            write_clipboard_cb: { _, _, _, _, _ in },
            close_surface_cb: { _, _ in }
        )
    }

    private nonisolated static func onWakeup(_ userdata: UnsafeMutableRawPointer?) {
        _ = userdata
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                GhosttyiOSApp.shared.tick()
            }
        }
    }
}
#endif
