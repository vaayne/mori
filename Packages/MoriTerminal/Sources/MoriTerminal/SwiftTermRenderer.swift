#if os(iOS)
import SwiftTerm
import UIKit

/// Callback fired when the terminal wants to send data back (user keystrokes).
public typealias SwiftTermInputHandler = @MainActor (Data) -> Void

/// Callback fired when the terminal grid dimensions change.
public typealias SwiftTermSizeChangeHandler = @MainActor (UInt16, UInt16) -> Void

/// Thin UIView wrapper around SwiftTerm's `TerminalView` for the iOS remote terminal.
///
/// Exposes the same minimal API that `GhosttyiOSRenderer` provided:
/// - `feedBytes(_:)` to push terminal output
/// - `gridSize()` to read current column/row count
///
/// Additionally wires SwiftTerm's native keyboard input and resize callbacks
/// back to the coordinator via closures.
@MainActor
public final class SwiftTermRenderer: UIView {

    private let terminalView: TerminalView

    /// Called when the user types on the iOS keyboard (raw bytes from the VT emulator).
    public var inputHandler: SwiftTermInputHandler?

    /// Called when the terminal grid dimensions change (e.g. device rotation).
    public var sizeChangeHandler: SwiftTermSizeChangeHandler?

    public init(
        frame: CGRect = .zero,
        inputHandler: SwiftTermInputHandler? = nil,
        sizeChangeHandler: SwiftTermSizeChangeHandler? = nil
    ) {
        self.inputHandler = inputHandler
        self.sizeChangeHandler = sizeChangeHandler
        self.terminalView = TerminalView(frame: frame)
        super.init(frame: frame)

        backgroundColor = .black
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminalView)
        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: topAnchor),
            terminalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminalView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        terminalView.terminalDelegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public API

    /// Feed raw terminal output bytes (from SSH / tmux) into the emulator.
    public func feedBytes(_ data: Data) {
        let slice = Array(data)[...]
        terminalView.feed(byteArray: slice)
    }

    /// Current terminal grid dimensions.
    public func gridSize() -> (cols: UInt16, rows: UInt16) {
        let terminal = terminalView.getTerminal()
        return (UInt16(terminal.cols), UInt16(terminal.rows))
    }

    /// Make the embedded terminal view first responder to show the iOS keyboard.
    public func activateKeyboard() {
        _ = terminalView.becomeFirstResponder()
    }
}

// MARK: - TerminalViewDelegate

extension SwiftTermRenderer: @preconcurrency TerminalViewDelegate {
    public func send(source: TerminalView, data: ArraySlice<UInt8>) {
        inputHandler?(Data(data))
    }

    public func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        sizeChangeHandler?(UInt16(newCols), UInt16(newRows))
    }

    public func setTerminalTitle(source: TerminalView, title: String) {}

    public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    public func scrolled(source: TerminalView, position: Double) {}

    public func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link) else { return }
        UIApplication.shared.open(url)
    }

    public func clipboardCopy(source: TerminalView, content: Data) {
        if let string = String(data: content, encoding: .utf8) {
            UIPasteboard.general.string = string
        }
    }

    public func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
#endif
