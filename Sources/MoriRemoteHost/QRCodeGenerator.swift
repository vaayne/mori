import Foundation
import AppKit
import CoreImage

/// Generates QR codes using CoreImage's CIQRCodeGenerator filter.
enum QRCodeGenerator {

    /// Generate a QR code as PNG data.
    /// - Parameter content: The string to encode in the QR code.
    /// - Returns: PNG data, or nil if generation failed.
    static func generatePNG(from content: String, size: CGFloat = 512) -> Data? {
        guard let ciImage = generateCIImage(from: content) else { return nil }

        // Scale the QR code to the desired size
        let scaleX = size / ciImage.extent.width
        let scaleY = size / ciImage.extent.height
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return nil
        }

        let nsImage = NSBitmapImageRep(cgImage: cgImage)
        return nsImage.representation(using: .png, properties: [:])
    }

    /// Generate an ASCII representation of the QR code for terminal display.
    /// Uses Unicode block characters for a compact representation.
    static func generateASCII(from content: String) -> String? {
        guard let ciImage = generateCIImage(from: content) else { return nil }

        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height

        guard let pixelData = cgImage.dataProvider?.data,
              let data = CFDataGetBytePtr(pixelData) else {
            return nil
        }

        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow

        var result = ""

        // Use two rows per character line with Unicode half-blocks
        // Top half = upper block, bottom half = lower block
        var y = 0
        while y < height {
            for x in 0..<width {
                let topOffset = y * bytesPerRow + x * bytesPerPixel
                let topIsBlack = data[topOffset] == 0

                let bottomIsBlack: Bool
                if y + 1 < height {
                    let bottomOffset = (y + 1) * bytesPerRow + x * bytesPerPixel
                    bottomIsBlack = data[bottomOffset] == 0
                } else {
                    bottomIsBlack = false
                }

                switch (topIsBlack, bottomIsBlack) {
                case (true, true):
                    result.append("\u{2588}")   // Full block
                case (true, false):
                    result.append("\u{2580}")   // Upper half block
                case (false, true):
                    result.append("\u{2584}")   // Lower half block
                case (false, false):
                    result.append(" ")          // Space
                }
            }
            result.append("\n")
            y += 2
        }

        return result
    }

    // MARK: - Private

    private static func generateCIImage(from content: String) -> CIImage? {
        guard let data = content.data(using: .utf8) else { return nil }

        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel") // Medium error correction

        return filter.outputImage
    }
}
