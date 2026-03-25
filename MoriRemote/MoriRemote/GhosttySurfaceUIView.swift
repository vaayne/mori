import UIKit
import GhosttyKit

/// Sendable wrapper for the raw pointer to cross isolation boundaries in deinit.
private struct SendableSurface: @unchecked Sendable {
    let pointer: ghostty_surface_t
}

/// UIView subclass that hosts a ghostty terminal surface on iOS.
/// Uses CAMetalLayer for GPU-accelerated rendering.
@MainActor
final class GhosttySurfaceUIView: UIView {

    nonisolated(unsafe) private(set) var surface: ghostty_surface_t?

    override class var layerClass: AnyClass { CAMetalLayer.self }

    init(app: ghostty_app_t) {
        // Non-zero initial frame required for Metal renderer init
        super.init(frame: CGRect(x: 0, y: 0, width: 800, height: 600))

        backgroundColor = .black

        // Configure Metal layer
        if let metalLayer = layer as? CAMetalLayer {
            metalLayer.contentsScale = UIScreen.main.scale
        }

        // Create surface config
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

        guard let surface = ghostty_surface_new(app, &config) else {
            NSLog("[GhosttySurfaceUIView] ghostty_surface_new failed")
            return
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
}
