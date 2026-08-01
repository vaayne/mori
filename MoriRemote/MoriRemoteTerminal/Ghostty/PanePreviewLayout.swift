import CoreGraphics
import UIKit

/// Single source of truth for pane-preview tile geometry and the physical
/// pixel budget used when downscaling local renderer frames.
///
/// Used by:
/// - `GhosttyPanePreviewSession` for the local image budget
/// - `GhosttyPaneSelectionTile` for fixed tile sizing
///
/// Capture once per session at session-init time. Rotation while the panes
/// sheet is open does not justify reissuing previews; we keep the originally
/// requested image regardless.
enum PanePreviewLayout {
    struct Metrics: Equatable {
        let columnCount: Int
        let tilePointSize: CGSize
        let previewPointSize: CGSize
        let gridSpacing: CGFloat
        let tilePadding: CGFloat

        func gridHeight(itemCount: Int) -> CGFloat {
            guard itemCount > 0 else { return 0 }
            let rows = (itemCount + columnCount - 1) / columnCount
            return CGFloat(rows) * tilePointSize.height
                + CGFloat(rows - 1) * gridSpacing
        }
    }

    /// Height for a selector sheet's scrollable grid. The whole grid shows
    /// exactly whenever it fits within the height budget — the sheet grows
    /// rather than hiding part of the final row. Only grids larger than the
    /// budget scroll, showing complete rows plus half of the next tile so
    /// the cut is an unmistakable scroll affordance.
    @MainActor
    static func gridIdealHeight(itemCount: Int, metrics: Metrics) -> CGFloat {
        let fullHeight = metrics.gridHeight(itemCount: itemCount)
        let budget = UIScreen.main.bounds.height * 0.72
        guard fullHeight > budget else { return fullHeight }

        let tile = metrics.tilePointSize.height
        let spacing = metrics.gridSpacing
        let peek = tile * 0.5

        func height(fullRows: Int) -> CGFloat {
            CGFloat(fullRows) * tile + CGFloat(fullRows - 1) * spacing + spacing + peek
        }

        var rows = 1
        while height(fullRows: rows + 1) <= budget {
            rows += 1
        }
        return min(height(fullRows: rows), fullHeight)
    }

    private static let defaultSheetContentWidth: CGFloat = 361
    private static let sheetHorizontalPadding: CGFloat = 32
    private static let defaultPreviewAspectRatio: CGFloat = 4.0 / 3.0
    private static let tilePadding: CGFloat = 8
    private static let captionHeight: CGFloat = 14
    private static let windowCaptionHeight: CGFloat = 30
    private static let tileCaptionSpacing: CGFloat = 6
    private static let maxSingleTileWidth: CGFloat = 390

    /// Window grid uses a fixed two-column layout. The "New Window" affordance
    /// is a fixed sheet action, not a trailing grid cell, so dense sessions can
    /// scroll windows without hiding the create command.
    private static let windowGridColumnCount: Int = 2
    private static let windowGridSpacing: CGFloat = 10

    static func metrics(for paneCount: Int) -> Metrics {
        metrics(for: paneCount, availableWidth: defaultSheetContentWidth)
    }

    static func metrics(
        for paneCount: Int,
        availableWidth: CGFloat
    ) -> Metrics {
        let paneCount = max(paneCount, 1)
        let columnCount = paneCount == 1 ? 1 : 2
        let gridSpacing: CGFloat = paneCount == 1 ? 12 : 10
        let safeAvailableWidth = max(availableWidth, 1)
        let contentWidth = paneCount == 1
            ? min(safeAvailableWidth, maxSingleTileWidth)
            : safeAvailableWidth
        let totalGridSpacing = CGFloat(columnCount - 1) * gridSpacing
        let tileWidth = max(
            1,
            floor((contentWidth - totalGridSpacing) / CGFloat(columnCount))
        )
        let previewWidth = max(1, tileWidth - tilePadding * 2)
        let previewHeight = ceil(previewWidth / defaultPreviewAspectRatio)
        let tileHeight = previewHeight + tileCaptionSpacing + captionHeight + tilePadding * 2
        return .init(
            columnCount: columnCount,
            tilePointSize: CGSize(width: tileWidth, height: tileHeight),
            previewPointSize: CGSize(width: previewWidth, height: previewHeight),
            gridSpacing: gridSpacing,
            tilePadding: tilePadding
        )
    }

    /// Display scale captured once at session init. Avoids touching
    /// UIScreen.main during request construction or rendering.
    @MainActor
    static func currentScale() -> CGFloat {
        let scale = UIScreen.main.scale
        return scale.isFinite && scale > 0 ? scale : 1
    }

    @MainActor
    static func currentSheetContentWidth() -> CGFloat {
        let width = UIScreen.main.bounds.width - sheetHorizontalPadding
        return width.isFinite && width > 0 ? width : defaultSheetContentWidth
    }

    @MainActor
    static func metricsForCurrentScreen(for paneCount: Int) -> Metrics {
        metrics(for: paneCount, availableWidth: currentSheetContentWidth())
    }

    @MainActor
    static func windowMetricsForCurrentScreen() -> Metrics {
        windowMetrics(availableWidth: currentSheetContentWidth())
    }

    static func windowMetrics(
        availableWidth: CGFloat
    ) -> Metrics {
        let safeAvailableWidth = max(availableWidth, 1)
        let columnCount = windowGridColumnCount
        let totalGridSpacing = CGFloat(columnCount - 1) * windowGridSpacing
        let tileWidth = max(
            1,
            floor((safeAvailableWidth - totalGridSpacing) / CGFloat(columnCount))
        )
        let previewWidth = max(1, tileWidth - tilePadding * 2)
        let previewHeight = ceil(previewWidth / defaultPreviewAspectRatio)
        let tileHeight = previewHeight + tileCaptionSpacing + windowCaptionHeight + tilePadding * 2
        return .init(
            columnCount: columnCount,
            tilePointSize: CGSize(width: tileWidth, height: tileHeight),
            previewPointSize: CGSize(width: previewWidth, height: previewHeight),
            gridSpacing: windowGridSpacing,
            tilePadding: tilePadding
        )
    }

    /// Physical pixel budget for local picker images at the given display
    /// scale. Returned dimensions are clamped to UInt32.
    @MainActor
    static func physicalPixelBudget(
        paneCount: Int,
        scale: CGFloat
    ) -> (width: UInt32, height: UInt32) {
        physicalPixelBudget(
            paneCount: paneCount,
            availableWidth: currentSheetContentWidth(),
            scale: scale
        )
    }

    static func physicalPixelBudget(
        paneCount: Int,
        availableWidth: CGFloat,
        scale: CGFloat
    ) -> (width: UInt32, height: UInt32) {
        let metrics = metrics(for: paneCount, availableWidth: availableWidth)
        let safeScale = max(scale, 1)
        let widthPx = (metrics.previewPointSize.width * safeScale).rounded(.up)
        let heightPx = (metrics.previewPointSize.height * safeScale).rounded(.up)
        return (
            clampUInt32(widthPx),
            clampUInt32(heightPx)
        )
    }

    @MainActor
    static func windowPhysicalPixelBudget(
        scale: CGFloat
    ) -> (width: UInt32, height: UInt32) {
        windowPhysicalPixelBudget(
            availableWidth: currentSheetContentWidth(),
            scale: scale
        )
    }

    static func windowPhysicalPixelBudget(
        availableWidth: CGFloat,
        scale: CGFloat
    ) -> (width: UInt32, height: UInt32) {
        let metrics = windowMetrics(availableWidth: availableWidth)
        let safeScale = max(scale, 1)
        let widthPx = (metrics.previewPointSize.width * safeScale).rounded(.up)
        let heightPx = (metrics.previewPointSize.height * safeScale).rounded(.up)
        return (
            clampUInt32(widthPx),
            clampUInt32(heightPx)
        )
    }

    private static func clampUInt32(_ value: CGFloat) -> UInt32 {
        guard value.isFinite, value > 0 else { return 1 }
        let clamped = min(value, CGFloat(UInt32.max))
        return max(1, UInt32(clamped))
    }
}
