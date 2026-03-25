import UIKit
import GhosttyKit

/// Manages the ghostty application context for the iOS app.
/// Simplified version of the macOS GhosttyApp — no action handler, no tmux integration.
@MainActor
final class GhosttyAppContext {
    static let shared = GhosttyAppContext()

    private(set) var app: ghostty_app_t?

    private init() {
        guard let config = buildConfig() else {
            NSLog("[GhosttyAppContext] failed to create config")
            return
        }

        let userdata = Unmanaged.passUnretained(self).toOpaque()
        var runtimeConfig = Self.makeRuntimeConfig(userdata: userdata)

        guard let app = ghostty_app_new(&runtimeConfig, config) else {
            NSLog("[GhosttyAppContext] ghostty_app_new failed")
            ghostty_config_free(config)
            return
        }

        self.app = app
        ghostty_config_free(config)
    }

    // MARK: - Config

    private func buildConfig() -> ghostty_config_t? {
        guard let config = ghostty_config_new() else { return nil }

        // Load user's ghostty config if available
        let userConfig = NSHomeDirectory() + "/.config/ghostty/config"
        if FileManager.default.fileExists(atPath: userConfig) {
            ghostty_config_load_file(config, userConfig)
        }

        // iOS embedding overrides — write to temp file since there's no string loading API
        let overrides = """
        window-decoration = false
        confirm-close-surface = false
        quit-after-last-window-closed = false
        """
        let overridePath = NSTemporaryDirectory() + "ghostty-mori-remote-overrides.conf"
        try? overrides.write(toFile: overridePath, atomically: true, encoding: .utf8)
        ghostty_config_load_file(config, overridePath)

        ghostty_config_finalize(config)
        return config
    }

    // MARK: - Event Loop

    func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    // MARK: - Runtime Config

    private nonisolated static func makeRuntimeConfig(
        userdata: UnsafeMutableRawPointer
    ) -> ghostty_runtime_config_s {
        ghostty_runtime_config_s(
            userdata: userdata,
            supports_selection_clipboard: false,
            wakeup_cb: { userdata in GhosttyAppContext.onWakeup(userdata) },
            action_cb: { _, _, _ in false },
            read_clipboard_cb: { userdata, loc, state in
                GhosttyAppContext.onReadClipboard(userdata, state: state)
            },
            confirm_read_clipboard_cb: { _, _, state, _ in
                // Auto-confirm clipboard reads on iOS
                if let state { /* no-op for now */ }
            },
            write_clipboard_cb: { _, _, content, len, _ in
                GhosttyAppContext.onWriteClipboard(content, len: len)
            },
            close_surface_cb: { _, _ in }
        )
    }

    // MARK: - Callbacks

    private nonisolated static func onWakeup(_ userdata: UnsafeMutableRawPointer?) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                GhosttyAppContext.shared.tick()
            }
        }
    }

    private nonisolated static func onReadClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        state: UnsafeMutableRawPointer?
    ) -> Bool {
        // Clipboard read not supported in this shell app
        false
    }

    private nonisolated static func onWriteClipboard(
        _ content: UnsafePointer<ghostty_clipboard_content_s>?,
        len: Int
    ) {
        guard let content, len > 0 else { return }
        for i in 0..<len {
            let item = content[i]
            guard let mime = item.mime, let data = item.data else { continue }
            if String(cString: mime) == "text/plain" {
                let text = String(cString: data)
                DispatchQueue.main.async {
                    UIPasteboard.general.string = text
                }
                break
            }
        }
    }
}
