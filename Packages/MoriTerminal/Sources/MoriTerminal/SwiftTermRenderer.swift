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

    /// Tracks whether the initial size report has been sent after layout.
    private var didReportInitialSize = false

    /// Called once after the first layout with valid grid dimensions.
    public var initialLayoutHandler: ((UInt16, UInt16) -> Void)?

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

        // Prevent UIScrollView from dismissing the keyboard on scroll/drag.
        terminalView.keyboardDismissMode = .none

        // Hide the blinking cursor caret that iOS renders for UITextInput views.
        // SwiftTerm draws its own cursor in the terminal grid.
        terminalView.tintColor = .clear

        // Set explicit terminal colors so the draw method fills with an opaque
        // background. SwiftTerm defaults nativeBackgroundColor to .clear which
        // causes old content to show through after `clear` or scrollback changes.
        terminalView.nativeBackgroundColor = .black
        terminalView.nativeForegroundColor = UIColor(white: 0.84, alpha: 1.0)

        setupAlternateScreenScroll()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    public override func layoutSubviews() {
        super.layoutSubviews()

        // After the first real layout, report the correct grid size.
        // SwiftTerm calculates cols/rows from its frame, which isn't
        // available during makeUIView.
        if !didReportInitialSize && bounds.width > 0 && bounds.height > 0 {
            let size = gridSize()
            if size.cols > 0 && size.rows > 0 {
                didReportInitialSize = true
                sizeChangeHandler?(size.cols, size.rows)
                initialLayoutHandler?(size.cols, size.rows)
                initialLayoutHandler = nil
            }
        }
    }

    // MARK: - Public API

    /// Feed raw terminal output bytes (from SSH / tmux) into the emulator.
    public func feedBytes(_ data: Data) {
        data.withUnsafeBytes { ptr in
            let slice = ptr.bindMemory(to: UInt8.self)
            terminalView.feed(byteArray: ArraySlice(slice))
        }
        syncScrollEnabled()
    }

    /// Current terminal grid dimensions.
    public func gridSize() -> (cols: UInt16, rows: UInt16) {
        let terminal = terminalView.getTerminal()
        return (UInt16(terminal.cols), UInt16(terminal.rows))
    }

    /// The underlying SwiftTerm `TerminalView` — exposed so callers can set
    /// a custom `inputAccessoryView` and send keys directly.
    public var swiftTermView: TerminalView { terminalView }

    /// Make the embedded terminal view first responder to show the iOS keyboard.
    public func activateKeyboard() {
        _ = terminalView.becomeFirstResponder()
    }

    /// Resign first responder to dismiss the iOS keyboard.
    public func deactivateKeyboard() {
        _ = terminalView.resignFirstResponder()
    }

    // MARK: - Alternate Screen Scroll

    /// Pan gesture that sends mouse wheel events when the terminal is in
    /// alternate screen mode (e.g. tmux) and the running application has
    /// enabled mouse reporting.
    private var alternateScrollGesture: UIPanGestureRecognizer?

    /// Accumulated vertical translation used to throttle scroll events
    /// to roughly one event per terminal-row of finger movement.
    private var accumulatedScrollDelta: CGFloat = 0

    private func setupAlternateScreenScroll() {
        let gesture = UIPanGestureRecognizer(
            target: self,
            action: #selector(handleAlternateScreenScroll(_:))
        )
        gesture.delegate = self
        terminalView.addGestureRecognizer(gesture)
        alternateScrollGesture = gesture
    }

    /// Disable UIScrollView scrolling when the terminal cannot scroll
    /// (alternate screen buffer has no scrollback). This prevents the
    /// useless bounce effect and allows our gesture to take over.
    private func syncScrollEnabled() {
        let canScroll = terminalView.canScroll
        if terminalView.isScrollEnabled != canScroll {
            terminalView.isScrollEnabled = canScroll
        }
    }

    @objc private func handleAlternateScreenScroll(
        _ gesture: UIPanGestureRecognizer
    ) {
        let terminal = terminalView.getTerminal()
        guard terminal.mouseMode != .off else { return }

        switch gesture.state {
        case .began:
            accumulatedScrollDelta = 0

        case .changed:
            let translation = gesture.translation(in: terminalView)
            gesture.setTranslation(.zero, in: terminalView)
            accumulatedScrollDelta += translation.y

            let rows = CGFloat(terminal.rows)
            guard rows > 0 else { return }
            let cellHeight = terminalView.bounds.height / rows
            guard cellHeight > 0 else { return }

            let cols = CGFloat(terminal.cols)
            let cellWidth = cols > 0 ? terminalView.bounds.width / cols : 8
            let location = gesture.location(in: terminalView)
            let col = min(max(0, Int(location.x / cellWidth)), terminal.cols - 1)
            let row = min(max(0, Int(location.y / cellHeight)), terminal.rows - 1)

            while abs(accumulatedScrollDelta) >= cellHeight {
                if accumulatedScrollDelta > 0 {
                    // Finger moved down → scroll up (show earlier content)
                    let flags = terminal.encodeButton(
                        button: 4, release: false,
                        shift: false, meta: false, control: false
                    )
                    terminal.sendEvent(buttonFlags: flags, x: col, y: row)
                    accumulatedScrollDelta -= cellHeight
                } else {
                    // Finger moved up → scroll down (show later content)
                    let flags = terminal.encodeButton(
                        button: 5, release: false,
                        shift: false, meta: false, control: false
                    )
                    terminal.sendEvent(buttonFlags: flags, x: col, y: row)
                    accumulatedScrollDelta += cellHeight
                }
            }

        case .ended, .cancelled:
            accumulatedScrollDelta = 0

        default:
            break
        }
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

    public func scrolled(source: TerminalView, position: Double) {
        syncScrollEnabled()
    }

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

// MARK: - UIGestureRecognizerDelegate

extension SwiftTermRenderer: UIGestureRecognizerDelegate {

    /// Only begin the alternate-screen scroll gesture when:
    /// 1. The pan is primarily vertical
    /// 2. The terminal cannot scroll (alternate screen / no scrollback)
    /// 3. The running application has enabled mouse reporting
    public override func gestureRecognizerShouldBegin(
        _ gestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard gestureRecognizer === alternateScrollGesture,
              let pan = gestureRecognizer as? UIPanGestureRecognizer
        else { return true }

        let velocity = pan.velocity(in: pan.view)
        let isVertical = abs(velocity.y) > abs(velocity.x)
        let terminal = terminalView.getTerminal()

        return isVertical
            && !terminalView.canScroll
            && terminal.mouseMode != .off
    }

    /// When our gesture might activate, require SwiftTerm's own pan gestures
    /// (panMouseGesture, UIScrollView pan) to wait for ours to fail first.
    /// This prevents click-drag mouse events from firing during a scroll.
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard gestureRecognizer === alternateScrollGesture,
              otherGestureRecognizer is UIPanGestureRecognizer
        else { return false }

        let terminal = terminalView.getTerminal()
        return !terminalView.canScroll && terminal.mouseMode != .off
    }
}
#endif
