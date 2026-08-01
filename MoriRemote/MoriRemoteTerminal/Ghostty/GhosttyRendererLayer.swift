import IOSurface
import QuartzCore

/// Locates Ghostty's renderer layer and reads only publication geometry.
/// Pixel capture belonged to the removed pane-preview feature.
enum GhosttyRendererLayer {
    static func find(in viewLayer: CALayer) -> CALayer? {
        let layers = viewLayer.sublayers ?? []
        if let published = layers.first(where: { iosurface(from: $0) != nil }) {
            return published
        }
        // Ghostty installs exactly one direct renderer sublayer before its
        // first IOSurface publication.
        return layers.count == 1 ? layers[0] : nil
    }

    static func dimensions(in layer: CALayer) -> (width: Int, height: Int)? {
        guard let surface = iosurface(from: layer) else { return nil }
        return (IOSurfaceGetWidth(surface), IOSurfaceGetHeight(surface))
    }

    private static func iosurface(from layer: CALayer) -> IOSurface? {
        guard let contents = layer.contents else { return nil }
        let value = contents as CFTypeRef
        guard CFGetTypeID(value) == IOSurfaceGetTypeID() else { return nil }
        return unsafeDowncast(contents as AnyObject, to: IOSurface.self)
    }
}
