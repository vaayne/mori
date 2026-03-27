import AppKit
import GhosttyKit

public extension Notification.Name {
    static let ghosttySurfaceDidClose = Notification.Name("MoriTerminal.GhosttySurfaceDidClose")
}

/// Actions that Mori intercepts from ghostty keybindings.
/// Ghostty maps keys to these intents; Mori provides the tmux implementation.
public enum GhosttyAppAction: Sendable {
    case newTab
    case closeTab
    case gotoTab(GotoTab)
    case newSplit(SplitDirection)
    case gotoSplit(GotoSplit)
    case resizeSplit(ResizeSplit, amount: UInt16)
    case equalizeSplits
    case toggleSplitZoom
    case newWindow
    case closeWindow
    case openConfig
    case toggleFullscreen

    public enum GotoTab: Sendable {
        case previous, next, last, index(Int)
    }

    public enum SplitDirection: Sendable {
        case right, down, left, up
    }

    public enum GotoSplit: Sendable {
        case previous, next, up, down, left, right
    }

    public enum ResizeSplit: Sendable {
        case up, down, left, right
    }
}

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

    /// Callback for ghostty actions that Mori intercepts (tabs, splits, etc.).
    /// Set by the app target to redirect ghostty intents to WorkspaceManager/tmux.
    var actionHandler: (@MainActor (GhosttyAppAction) -> Void)?

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
        let moriAction: GhosttyAppAction
        switch action.tag {
        case GHOSTTY_ACTION_NEW_TAB:
            moriAction = .newTab
        case GHOSTTY_ACTION_CLOSE_TAB:
            moriAction = .closeTab
        case GHOSTTY_ACTION_GOTO_TAB:
            let raw = action.action.goto_tab
            switch raw {
            case GHOSTTY_GOTO_TAB_PREVIOUS: moriAction = .gotoTab(.previous)
            case GHOSTTY_GOTO_TAB_NEXT: moriAction = .gotoTab(.next)
            case GHOSTTY_GOTO_TAB_LAST: moriAction = .gotoTab(.last)
            default:
                // Positive raw values are 1-based tab indices
                let index = Int(raw.rawValue)
                guard index > 0 else { return false }
                moriAction = .gotoTab(.index(index))
            }
        case GHOSTTY_ACTION_NEW_SPLIT:
            switch action.action.new_split {
            case GHOSTTY_SPLIT_DIRECTION_RIGHT: moriAction = .newSplit(.right)
            case GHOSTTY_SPLIT_DIRECTION_DOWN: moriAction = .newSplit(.down)
            case GHOSTTY_SPLIT_DIRECTION_LEFT: moriAction = .newSplit(.left)
            case GHOSTTY_SPLIT_DIRECTION_UP: moriAction = .newSplit(.up)
            default: return false
            }
        case GHOSTTY_ACTION_GOTO_SPLIT:
            switch action.action.goto_split {
            case GHOSTTY_GOTO_SPLIT_PREVIOUS: moriAction = .gotoSplit(.previous)
            case GHOSTTY_GOTO_SPLIT_NEXT: moriAction = .gotoSplit(.next)
            case GHOSTTY_GOTO_SPLIT_UP: moriAction = .gotoSplit(.up)
            case GHOSTTY_GOTO_SPLIT_DOWN: moriAction = .gotoSplit(.down)
            case GHOSTTY_GOTO_SPLIT_LEFT: moriAction = .gotoSplit(.left)
            case GHOSTTY_GOTO_SPLIT_RIGHT: moriAction = .gotoSplit(.right)
            default: return false
            }
        case GHOSTTY_ACTION_RESIZE_SPLIT:
            let rs = action.action.resize_split
            let dir: GhosttyAppAction.ResizeSplit
            switch rs.direction {
            case GHOSTTY_RESIZE_SPLIT_UP: dir = .up
            case GHOSTTY_RESIZE_SPLIT_DOWN: dir = .down
            case GHOSTTY_RESIZE_SPLIT_LEFT: dir = .left
            case GHOSTTY_RESIZE_SPLIT_RIGHT: dir = .right
            default: return false
            }
            moriAction = .resizeSplit(dir, amount: rs.amount)
        case GHOSTTY_ACTION_EQUALIZE_SPLITS:
            moriAction = .equalizeSplits
        case GHOSTTY_ACTION_TOGGLE_SPLIT_ZOOM:
            moriAction = .toggleSplitZoom
        case GHOSTTY_ACTION_NEW_WINDOW:
            moriAction = .newWindow
        case GHOSTTY_ACTION_CLOSE_WINDOW:
            moriAction = .closeWindow
        case GHOSTTY_ACTION_OPEN_CONFIG:
            moriAction = .openConfig
        case GHOSTTY_ACTION_TOGGLE_FULLSCREEN:
            moriAction = .toggleFullscreen
        default:
            return false
        }

        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                GhosttyApp.shared.actionHandler?(moriAction)
            }
        }
        return true
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
        guard let userdata else { return }
        let rawUserdata = UInt(bitPattern: userdata)

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .ghosttySurfaceDidClose,
                object: nil,
                userInfo: [
                    "userdata": rawUserdata,
                    "processAlive": processAlive,
                ]
            )
        }
    }
}
