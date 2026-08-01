struct TmuxControlViewport: Equatable, Sendable {
    static let `default` = TmuxControlViewport(
        columns: 120,
        rows: 40,
        pixelWidth: 0,
        pixelHeight: 0
    )

    let columns: UInt16
    let rows: UInt16
    let pixelWidth: UInt32
    let pixelHeight: UInt32
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
