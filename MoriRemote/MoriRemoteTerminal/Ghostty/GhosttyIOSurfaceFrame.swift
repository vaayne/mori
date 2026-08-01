import CoreGraphics
import Foundation
import IOSurface
import QuartzCore

/// Swift-owned pixels copied from one frame already published by Ghostty's
/// IOSurface renderer layer. Reading never asks the renderer to draw.
struct GhosttyIOSurfaceFrame: Sendable {
    enum ReadError: Error {
        case lockFailed
        case invalidGeometry
        case unsupportedPixelFormat(UInt32)
        case imageCreationFailed
    }

    private static let bgraPixelFormat: UInt32 = 0x4247_5241

    let width: Int
    let height: Int
    let bytesPerRow: Int
    let bytes: Data

    static func rendererLayer(in viewLayer: CALayer) -> CALayer? {
        let layers = viewLayer.sublayers ?? []
        if let published = layers.first(where: { iosurface(from: $0) != nil }) {
            return published
        }
        // Ghostty's iOS Metal renderer installs exactly one direct sublayer.
        // Before its first frame that layer has no contents yet.
        return layers.count == 1 ? layers[0] : nil
    }

    static func dimensions(in layer: CALayer) -> (width: Int, height: Int)? {
        guard let surface = iosurface(from: layer) else { return nil }
        return (IOSurfaceGetWidth(surface), IOSurfaceGetHeight(surface))
    }

    /// Copies the currently published IOSurface while the caller still owns
    /// the layer publication boundary. Retaining the IOSurface is not enough:
    /// Metal reuses its fixed frame targets, so later draws may overwrite the
    /// same allocation even while another owner holds a CF reference.
    static func read(from layer: CALayer) throws -> Self {
        guard let surface = iosurface(from: layer) else {
            throw ReadError.invalidGeometry
        }
        guard IOSurfaceLock(surface, .readOnly, nil) == 0 else {
            throw ReadError.lockFailed
        }
        defer { IOSurfaceUnlock(surface, .readOnly, nil) }

        let width = IOSurfaceGetWidth(surface)
        let height = IOSurfaceGetHeight(surface)
        let bytesPerRow = IOSurfaceGetBytesPerRow(surface)
        guard width > 0, height > 0, bytesPerRow >= width * 4 else {
            throw ReadError.invalidGeometry
        }
        let optionalBase: UnsafeMutableRawPointer? = IOSurfaceGetBaseAddress(surface)
        guard let base = optionalBase else {
            throw ReadError.invalidGeometry
        }
        let pixelFormat = IOSurfaceGetPixelFormat(surface)
        guard pixelFormat == bgraPixelFormat else {
            throw ReadError.unsupportedPixelFormat(pixelFormat)
        }
        let (byteCount, overflow) = bytesPerRow.multipliedReportingOverflow(by: height)
        guard !overflow else { throw ReadError.invalidGeometry }
        return Self(
            width: width,
            height: height,
            bytesPerRow: bytesPerRow,
            bytes: Data(bytes: base, count: byteCount)
        )
    }

    func image(maxWidth: UInt32, maxHeight: UInt32) throws -> CGImage {
        guard maxWidth > 0, maxHeight > 0,
              let provider = CGDataProvider(data: bytes as CFData),
              let source = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: Self.colorSpace,
                bitmapInfo: Self.bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              )
        else { throw ReadError.imageCreationFailed }

        let scale = min(
            1,
            min(Double(maxWidth) / Double(width), Double(maxHeight) / Double(height))
        )
        guard scale < 1 else { return source }

        let targetWidth = max(1, Int((Double(width) * scale).rounded(.down)))
        let targetHeight = max(1, Int((Double(height) * scale).rounded(.down)))
        let targetBytesPerRow = targetWidth * 4
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: targetBytesPerRow,
            space: Self.colorSpace,
            bitmapInfo: Self.bitmapInfo.rawValue
        ) else { throw ReadError.imageCreationFailed }
        context.interpolationQuality = .medium
        context.draw(source, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        guard let image = context.makeImage() else { throw ReadError.imageCreationFailed }
        return image
    }

    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        ?? CGColorSpaceCreateDeviceRGB()
    private static let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
        CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)
    )

    private static func iosurface(from layer: CALayer) -> IOSurface? {
        guard let contents = layer.contents else { return nil }
        let value = contents as CFTypeRef
        guard CFGetTypeID(value) == IOSurfaceGetTypeID() else { return nil }
        return unsafeDowncast(contents as AnyObject, to: IOSurface.self)
    }
}
