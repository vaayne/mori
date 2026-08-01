import CoreGraphics

enum GhosttyViewportSizing {
    static func normalizedHeight(_ height: CGFloat) -> CGFloat {
        guard height.isFinite, height > 0 else { return 0 }
        return ceil(height)
    }
}

struct GhosttySoftwareKeyboardVisibility {
    static func visibleOverlapHeight(frameEnd: CGRect, screenBounds: CGRect) -> CGFloat {
        guard frameEnd.width > 0, frameEnd.height > 0,
              frameEnd.minY < screenBounds.maxY - 1
        else { return 0 }
        let overlap = frameEnd.intersection(screenBounds)
        guard !overlap.isNull, overlap.height.isFinite, overlap.height > 0 else { return 0 }
        return overlap.height
    }
}
