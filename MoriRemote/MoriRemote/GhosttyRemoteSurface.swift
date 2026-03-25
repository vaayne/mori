import UIKit
import GhosttyKit

/// UIView subclass that hosts a ghostty terminal surface using the Remote backend.
/// Instead of spawning a local pty (Exec backend), this passes pipe file descriptors
/// to ghostty so it uses the Remote termio backend for reading/writing terminal data.
@MainActor
final class GhosttyRemoteSurfaceView: UIView {

    nonisolated(unsafe) private(set) var surface: ghostty_surface_t?

    /// The pipe bridge that connects this surface to external data sources.
    let pipeBridge: PipeBridge

    override class var layerClass: AnyClass { CAMetalLayer.self }

    /// Initialize with the ghostty app context and a pre-created pipe bridge.
    init(app: ghostty_app_t, pipeBridge: PipeBridge) throws {
        self.pipeBridge = pipeBridge

        // Non-zero initial frame required for Metal renderer init
        super.init(frame: CGRect(x: 0, y: 0, width: 800, height: 600))

        backgroundColor = .black

        // Configure Metal layer
        if let metalLayer = layer as? CAMetalLayer {
            metalLayer.contentsScale = UIScreen.main.scale
        }

        // Create surface config with remote fd pair
        var config = ghostty_surface_config_new()
        config.platform_tag = GHOSTTY_PLATFORM_IOS
        config.platform = ghostty_platform_u(
            ios: ghostty_platform_ios_s(
                uiview: Unmanaged.passUnretained(self).toOpaque()
            )
        )
        config.userdata = Unmanaged.passUnretained(self).toOpaque()
        config.scale_factor = Double(UIScreen.main.scale)
        config.context = GHOSTTY_SURFACE_CONTEXT_WINDOW

        // Key: set remote fd pair so ghostty uses Remote backend instead of Exec
        config.remote_read_fd = pipeBridge.ghosttyReadFD
        config.remote_write_fd = pipeBridge.ghosttyWriteFD

        guard let surface = ghostty_surface_new(app, &config) else {
            NSLog("[GhosttyRemoteSurface] ghostty_surface_new failed")
            throw GhosttyRemoteSurfaceError.surfaceCreationFailed
        }

        self.surface = surface
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let surface {
            ghostty_surface_free(surface)
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let surface, bounds.width > 0, bounds.height > 0 else { return }
        let scale = UIScreen.main.scale
        ghostty_surface_set_size(
            surface,
            UInt32(bounds.width * scale),
            UInt32(bounds.height * scale)
        )
    }

    // MARK: - Focus

    func setFocus(_ focused: Bool) {
        guard let surface else { return }
        ghostty_surface_set_focus(surface, focused)
    }
}

// MARK: - Errors

enum GhosttyRemoteSurfaceError: Error, CustomStringConvertible {
    case surfaceCreationFailed

    var description: String {
        switch self {
        case .surfaceCreationFailed:
            "Failed to create ghostty surface with Remote backend"
        }
    }
}
