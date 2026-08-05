public struct TmuxControlViewport: Equatable, Sendable {
    public static let `default` = TmuxControlViewport(
        columns: 120,
        rows: 40,
        pixelWidth: 0,
        pixelHeight: 0
    )

    public let columns: UInt16
    public let rows: UInt16
    public let pixelWidth: UInt32
    public let pixelHeight: UInt32

    public init(columns: UInt16, rows: UInt16, pixelWidth: UInt32, pixelHeight: UInt32) {
        self.columns = columns
        self.rows = rows
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

extension TmuxControlViewport {
    init(clientSize: TmuxSessionController.ClientSize) {
        self.init(
            columns: Self.clampedCellCount(clientSize.cols),
            rows: Self.clampedCellCount(clientSize.rows),
            pixelWidth: 0,
            pixelHeight: 0
        )
    }

    private static func clampedCellCount(_ value: UInt32) -> UInt16 {
        UInt16(min(max(value, 2), UInt32(UInt16.max)))
    }
}
