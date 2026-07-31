import Darwin
import Foundation
import GhosttyKit
import UIKit

enum GhosttyKitRuntimeError: Error, Equatable, LocalizedError {
    case initializationFailed(Int32)
    case processDirectoryConfigurationFailed(String)
    case environmentConfigurationFailed(String)
    case configurationFileFailed(String)
    case configCreationFailed
    case appCreationFailed

    var errorDescription: String? {
        switch self {
        case .initializationFailed(let result): "Ghostty initialization failed (\(result))."
        case .processDirectoryConfigurationFailed(let path): "Ghostty could not prepare \(path)."
        case .environmentConfigurationFailed(let name): "Ghostty could not configure \(name)."
        case .configurationFileFailed(let path): "Ghostty could not write its terminal configuration at \(path)."
        case .configCreationFailed: "Ghostty could not create its terminal configuration."
        case .appCreationFailed: "Ghostty could not create its rendering runtime."
        }
    }
}

/// Process-wide Ghostty owner. iOS has no useful process HOME by default in the
/// simulator; configure the XDG roots before ghostty_init so font/config lookup
/// has the same prerequisites as the upstream renderer.
@MainActor
final class GhosttyKitRuntime {
    private static var didInitialize = false
    private let state: State
    private let callbacks: Callbacks

    private final class State: @unchecked Sendable {
        let app: ghostty_app_t
        let config: ghostty_config_t
        init(app: ghostty_app_t, config: ghostty_config_t) { self.app = app; self.config = config }
        func release() { ghostty_app_free(app); ghostty_config_free(config) }
    }

    init() throws {
        try Self.initializeBackend()
        guard let config = ghostty_config_new() else { throw GhosttyKitRuntimeError.configCreationFailed }
        do {
            try Self.loadMinimumTerminalConfiguration(into: config)
        } catch {
            ghostty_config_free(config)
            throw error
        }
        ghostty_config_finalize(config)
        let callbacks = Callbacks()
        var runtimeConfig = ghostty_runtime_config_s(
            userdata: callbacks.userdata,
            supports_selection_clipboard: true,
            wakeup_cb: Callbacks.wakeup,
            action_cb: Callbacks.action,
            read_clipboard_cb: nil,
            confirm_read_clipboard_cb: nil,
            write_clipboard_cb: nil,
            close_surface_cb: nil
        )
        guard let app = ghostty_app_new(&runtimeConfig, config) else {
            ghostty_config_free(config)
            throw GhosttyKitRuntimeError.appCreationFailed
        }
        state = State(app: app, config: config)
        self.callbacks = callbacks
        callbacks.app = app
    }

    deinit { callbacks.app = nil; state.release() }

    var appHandle: ghostty_app_t { state.app }
    func surfaceConfig() -> ghostty_terminal_surface_config_s { ghostty_terminal_surface_config_new() }

    private static func initializeBackend() throws {
        guard !didInitialize else { return }
        try configureProcessDirectories()
        let result = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
        guard result == GHOSTTY_SUCCESS else { throw GhosttyKitRuntimeError.initializationFailed(result) }
        didInitialize = true
    }

    private static func configureProcessDirectories() throws {
        let home = NSHomeDirectory()
        let support = "\(home)/Library/Application Support"
        let caches = "\(home)/Library/Caches"
        for path in [support, caches] {
            do { try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true) }
            catch { throw GhosttyKitRuntimeError.processDirectoryConfigurationFailed(path) }
        }
        try setEnvironment("HOME", home)
        try setEnvironment("XDG_CONFIG_HOME", support)
        try setEnvironment("XDG_CACHE_HOME", caches)
        try setEnvironment("XDG_STATE_HOME", support)
    }

    private static func setEnvironment(_ name: String, _ value: String) throws {
        guard getenv(name) == nil else { return }
        let result = name.withCString { name in value.withCString { value in setenv(name, value, 1) } }
        guard result == 0 else { throw GhosttyKitRuntimeError.environmentConfigurationFailed(name) }
    }

    private static func loadMinimumTerminalConfiguration(into config: ghostty_config_t) throws {
        // Keep a concrete iOS-safe font size: default config can resolve to no
        // usable font when HOME/XDG are absent in Simulator.
        let contents = "font-size = 14\nfont-family = Menlo\nbackground = #20242c\nforeground = #e6eaf0\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mori-ghostty-\(UUID().uuidString).conf")
        do { try contents.write(to: url, atomically: true, encoding: .utf8) }
        catch { throw GhosttyKitRuntimeError.configurationFileFailed(url.path) }
        defer { try? FileManager.default.removeItem(at: url) }
        url.path.withCString { ghostty_config_load_file(config, $0) }
    }

    private final class Callbacks: @unchecked Sendable {
        var app: ghostty_app_t?
        var userdata: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }
        static let wakeup: ghostty_runtime_wakeup_cb = { userdata in
            guard let userdata else { return }
            let callbacks = Unmanaged<Callbacks>.fromOpaque(userdata).takeUnretainedValue()
            Task { @MainActor in if let app = callbacks.app { ghostty_app_tick(app) } }
        }
        static let action: ghostty_runtime_action_cb = { _, _, _ in true }
    }
}

final class GhosttySurfaceView: UIView {
    var drawSurface: (() -> Void)?
    var rendererHealthy = true
    override class var layerClass: AnyClass { CAMetalLayer.self }
    override func draw(_ rect: CGRect) { super.draw(rect); drawSurface?() }
    override func didMoveToWindow() { super.didMoveToWindow(); alignGhosttyRendererSublayers(); setNeedsDisplay() }
    override func layoutSubviews() { super.layoutSubviews(); alignGhosttyRendererSublayers() }
    func alignGhosttyRendererSublayers() {
        let scale = max(window?.screen.scale ?? contentScaleFactor, 1)
        contentScaleFactor = scale
        layer.contentsScale = scale
        for sublayer in layer.sublayers ?? [] { sublayer.frame = bounds; sublayer.contentsScale = scale }
    }
}
