#if os(iOS)
import GhosttyKit
import QuartzCore
import UIKit

/// Minimal iOS UIView wrapper around a single ghostty surface.
@MainActor
public final class GhosttyiOSRenderer: UIView {

    private var surface: ghostty_surface_t?
    private var displayLink: CADisplayLink?

    public override class var layerClass: AnyClass {
        CAMetalLayer.self
    }

    public override init(frame: CGRect) {
        let initialFrame = frame.size == .zero
            ? CGRect(x: 0, y: 0, width: 800, height: 600)
            : frame
        super.init(frame: initialFrame)
        isOpaque = true
        createSurfaceIfNeeded()
        startDisplayLinkIfNeeded()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        // Surface and display link cleanup must happen synchronously.
        // These are main-thread-only objects, and UIView.deinit is
        // always called on the main thread.
        MainActor.assumeIsolated {
            displayLink?.invalidate()
            if let surface {
                ghostty_surface_free(surface)
            }
        }
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            displayLink?.invalidate()
            displayLink = nil
        } else {
            startDisplayLinkIfNeeded()
            createSurfaceIfNeeded()
            updateSurfaceSize()
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        createSurfaceIfNeeded()
        updateSurfaceSize()
    }

    public func feedBytes(_ data: Data) {
        createSurfaceIfNeeded()
        guard let surface else { return }

        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            ghostty_surface_write_output(
                surface,
                baseAddress.assumingMemoryBound(to: CChar.self),
                UInt(bytes.count)
            )
        }
        ghostty_surface_refresh(surface)
    }

    public func gridSize() -> (cols: UInt16, rows: UInt16) {
        guard let surface else { return (0, 0) }
        let size = ghostty_surface_size(surface)
        return (size.columns, size.rows)
    }

    private func createSurfaceIfNeeded() {
        guard surface == nil else { return }
        surface = GhosttyiOSApp.shared.createSurface(
            view: self,
            scaleFactor: currentScaleFactor
        )
    }

    private func updateSurfaceSize() {
        guard let surface else { return }

        let scale = currentScaleFactor
        contentScaleFactor = CGFloat(scale)
        ghostty_surface_set_content_scale(surface, scale, scale)

        let width = max(1, Int(bounds.width * CGFloat(scale)))
        let height = max(1, Int(bounds.height * CGFloat(scale)))
        ghostty_surface_set_size(surface, UInt32(width), UInt32(height))
    }

    private var currentScaleFactor: Double {
        Double(window?.screen.scale ?? UIScreen.main.scale)
    }

    private func startDisplayLinkIfNeeded() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(handleDisplayLinkTick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc
    private func handleDisplayLinkTick() {
        GhosttyiOSApp.shared.tick()
        guard let surface else { return }
        ghostty_surface_draw(surface)
    }
}
#endif
