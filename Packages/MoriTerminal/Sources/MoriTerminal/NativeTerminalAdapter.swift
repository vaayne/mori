#if os(macOS)
import AppKit
import Darwin

/// PTY-based terminal adapter. Creates a pseudo-terminal, forks a child process
/// running the specified command, and renders output into an NSView with a monospace font.
/// Keyboard input is forwarded to the PTY.
///
/// This is the fallback implementation when libghostty is not available.
/// It provides a functional (though basic) terminal experience.
@MainActor
public final class NativeTerminalAdapter: TerminalHost {

    public init() {}

    public func createSurface(command: String, workingDirectory: String) -> NSView {
        let termView = PTYTerminalView(command: command, workingDirectory: workingDirectory)
        termView.start()
        return termView
    }

    public func destroySurface(_ surface: NSView) {
        guard let termView = surface as? PTYTerminalView else { return }
        termView.stop()
    }

    public func surfaceDidResize(_ surface: NSView, to size: NSSize) {
        guard let termView = surface as? PTYTerminalView else { return }
        termView.updatePTYSize()
    }

    public func focusSurface(_ surface: NSView) {
        guard let termView = surface as? PTYTerminalView else { return }
        termView.window?.makeFirstResponder(termView)
    }

}

// MARK: - PTYTerminalView

/// An NSView that hosts a pseudo-terminal.
/// Uses forkpty() to create a PTY pair, runs a shell command as the child process,
/// reads output via a FileHandle and displays it in a scrollable text view.
/// Keyboard events are forwarded as raw bytes to the PTY master fd.
public final class PTYTerminalView: NSView {

    // MARK: - Properties

    private let command: String
    private let workingDirectory: String

    private var masterFD: Int32 = -1
    private var childPID: pid_t = -1
    private var readHandle: FileHandle?
    private var readSource: DispatchSourceRead?

    private let scrollView = NSScrollView()
    private let textView = TerminalTextView()
    private var textStorage: NSTextStorage { textView.textStorage! }

    /// ANSI parser state
    private var parser = ANSIParser()

    /// Current text attributes for newly inserted text
    private var currentAttributes: [NSAttributedString.Key: Any] = [:]

    // MARK: - Init

    init(command: String, workingDirectory: String) {
        self.command = command
        self.workingDirectory = workingDirectory
        super.init(frame: .zero)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stopNonisolated()
    }

    // MARK: - Setup

    private func setupViews() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        let monoFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        currentAttributes = [
            .font: monoFont,
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black,
        ]

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.backgroundColor = .black
        textView.insertionPointColor = .white
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.textContainer?.widthTracksTextView = true
        textView.font = monoFont
        textView.textColor = .white
        textView.onKeyDown = { [weak self] event in
            self?.interpretKeyEvent(event)
        }

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .black
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    // MARK: - PTY Lifecycle

    func start() {
        var winSize = winsize()
        winSize.ws_col = UInt16(max(80, Int(bounds.width / 7.8)))
        winSize.ws_row = UInt16(max(24, Int(bounds.height / 16)))
        winSize.ws_xpixel = UInt16(bounds.width)
        winSize.ws_ypixel = UInt16(bounds.height)

        var masterFD: Int32 = 0
        let pid = forkpty(&masterFD, nil, nil, &winSize)

        if pid == -1 {
            appendText("[mori] Failed to create PTY: \(String(cString: strerror(errno)))\n")
            return
        }

        if pid == 0 {
            // Child process
            if !workingDirectory.isEmpty {
                chdir(workingDirectory)
            }

            // Set TERM for tmux compatibility
            setenv("TERM", "xterm-256color", 1)
            setenv("LANG", "en_US.UTF-8", 1)

            // Use execv since execl (variadic) is unavailable in Swift 6
            let shellPath = "/bin/zsh"
            let args = [shellPath, "-l", "-c", command]
            let cArgs = args.map { strdup($0) } + [nil]
            execv(shellPath, cArgs)
            _exit(1)
        }

        // Parent process
        self.masterFD = masterFD
        self.childPID = pid

        // Set master FD to non-blocking
        let flags = fcntl(masterFD, F_GETFL)
        _ = fcntl(masterFD, F_SETFL, flags | O_NONBLOCK)

        // Read output using GCD dispatch source.
        // Setup is extracted to a nonisolated static method so the closures
        // do not inherit @MainActor isolation from this NSView subclass.
        let weakSelf = WeakSendableRef(self)
        let source = Self.makeReadSource(masterFD: masterFD, weakRef: weakSelf)
        self.readSource = source
        source.resume()
    }

    /// Build the dispatch source on a nonisolated context so its closures
    /// don't inherit @MainActor isolation from PTYTerminalView.
    private nonisolated static func makeReadSource(
        masterFD: Int32,
        weakRef: WeakSendableRef<PTYTerminalView>
    ) -> DispatchSourceRead {
        let source = DispatchSource.makeReadSource(
            fileDescriptor: masterFD,
            queue: .global(qos: .userInteractive)
        )

        source.setEventHandler {
            var buffer = [UInt8](repeating: 0, count: 8192)
            let bytesRead = read(masterFD, &buffer, buffer.count)
            if bytesRead > 0 {
                let data = Data(buffer[0..<bytesRead])
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        weakRef.value?.handleOutput(data)
                    }
                }
            } else if bytesRead == 0 || (bytesRead < 0 && errno != EAGAIN && errno != EINTR) {
                source.cancel()
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        weakRef.value?.appendText("\n[mori] Process exited.\n")
                    }
                }
            }
        }

        source.setCancelHandler {
            if masterFD >= 0 {
                close(masterFD)
            }
        }

        return source
    }

    func stop() {
        // Signal the child process first
        if childPID > 0 {
            kill(childPID, SIGHUP)
            var status: Int32 = 0
            waitpid(childPID, &status, WNOHANG)
            childPID = -1
        }

        // Cancel the dispatch source — its cancel handler is the sole owner of FD closing
        readSource?.cancel()
        readSource = nil
    }

    /// Non-isolated cleanup for deinit.
    /// At deinit time the object has no remaining references so actor isolation
    /// cannot be violated. We use assumeIsolated to satisfy the compiler.
    private nonisolated func stopNonisolated() {
        MainActor.assumeIsolated {
            let pid = childPID
            let source = readSource
            if pid > 0 {
                kill(pid, SIGHUP)
            }
            source?.cancel()
        }
    }

    // MARK: - Output Handling

    private func handleOutput(_ data: Data) {
        guard let str = String(data: data, encoding: .utf8) else {
            // Fallback: try latin1
            if let latin1 = String(data: data, encoding: .isoLatin1) {
                appendText(latin1)
            }
            return
        }

        let segments = parser.parse(str)
        for segment in segments {
            switch segment {
            case .text(let text):
                appendText(text)
            case .sgr(let attrs):
                applyAttributes(attrs)
            case .cursorUp, .cursorDown, .cursorForward, .cursorBack:
                // Basic cursor movement — append as-is for now
                break
            case .clearScreen:
                clearScreen()
            case .clearLine:
                clearCurrentLine()
            case .carriageReturn:
                handleCarriageReturn()
            case .bell:
                NSSound.beep()
            case .setTitle(let title):
                // Could propagate to window title
                _ = title
            }
        }
    }

    private func appendText(_ text: String) {
        let attributed = NSAttributedString(string: text, attributes: currentAttributes)
        textStorage.append(attributed)
        scrollToBottom()
    }

    private func clearScreen() {
        textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: "")
    }

    private func clearCurrentLine() {
        let string = textStorage.string as NSString
        let lastNewline = string.range(of: "\n", options: .backwards)
        let lineStart = lastNewline.location == NSNotFound ? 0 : lastNewline.location + 1
        let range = NSRange(location: lineStart, length: string.length - lineStart)
        textStorage.replaceCharacters(in: range, with: "")
    }

    private func handleCarriageReturn() {
        // Move "cursor" to start of current line by removing text after last newline
        let string = textStorage.string as NSString
        let lastNewline = string.range(of: "\n", options: .backwards)
        let lineStart = lastNewline.location == NSNotFound ? 0 : lastNewline.location + 1
        let range = NSRange(location: lineStart, length: string.length - lineStart)
        textStorage.replaceCharacters(in: range, with: "")
    }

    private func scrollToBottom() {
        let range = NSRange(location: textStorage.length, length: 0)
        textView.scrollRangeToVisible(range)
    }

    private func applyAttributes(_ attrs: SGRAttributes) {
        var newAttrs = currentAttributes

        if let fg = attrs.foreground {
            newAttrs[.foregroundColor] = fg
        }
        if let bg = attrs.background {
            newAttrs[.backgroundColor] = bg
        }
        if attrs.reset {
            let font = currentAttributes[.font] as? NSFont ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            newAttrs = [
                .font: font,
                .foregroundColor: NSColor.white,
                .backgroundColor: NSColor.black,
            ]
        }
        if attrs.bold {
            if let font = newAttrs[.font] as? NSFont {
                newAttrs[.font] = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            }
        }
        if attrs.underline {
            newAttrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }

        currentAttributes = newAttrs
    }

    // MARK: - Keyboard Input

    public override var acceptsFirstResponder: Bool { true }

    public override func becomeFirstResponder() -> Bool {
        true
    }

    public override func keyDown(with event: NSEvent) {
        guard masterFD >= 0 else { return }
        interpretKeyEvent(event)
    }

    private func interpretKeyEvent(_ event: NSEvent) {
        // Handle special keys
        if let specialSequence = specialKeySequence(for: event) {
            writeToPTY(specialSequence)
            return
        }

        // Handle regular character input
        guard let characters = event.characters else { return }
        writeToPTY(characters)
    }

    private func specialKeySequence(for event: NSEvent) -> String? {
        let modifiers = event.modifierFlags

        switch event.keyCode {
        case 36: return "\r"           // Return
        case 48: return "\t"           // Tab
        case 51: return "\u{7f}"       // Delete (backspace)
        case 53: return "\u{1b}"       // Escape
        case 123: return "\u{1b}[D"    // Left arrow
        case 124: return "\u{1b}[C"    // Right arrow
        case 125: return "\u{1b}[B"    // Down arrow
        case 126: return "\u{1b}[A"    // Up arrow
        case 115: return "\u{1b}[H"    // Home
        case 119: return "\u{1b}[F"    // End
        case 116: return "\u{1b}[5~"   // Page Up
        case 121: return "\u{1b}[6~"   // Page Down
        case 117: return "\u{1b}[3~"   // Forward Delete
        default: break
        }

        // Ctrl+key combinations
        if modifiers.contains(.control), let chars = event.charactersIgnoringModifiers {
            if let scalar = chars.unicodeScalars.first {
                let value = scalar.value
                // Ctrl+A through Ctrl+Z
                if value >= 0x61 && value <= 0x7a {
                    let ctrlChar = Character(UnicodeScalar(value - 0x60)!)
                    return String(ctrlChar)
                }
                // Ctrl+C, Ctrl+D etc. from uppercase
                if value >= 0x41 && value <= 0x5a {
                    let ctrlChar = Character(UnicodeScalar(value - 0x40)!)
                    return String(ctrlChar)
                }
            }
        }

        return nil
    }

    private func writeToPTY(_ string: String) {
        guard masterFD >= 0, let data = string.data(using: .utf8) else { return }
        data.withUnsafeBytes { buffer in
            guard let ptr = buffer.baseAddress else { return }
            _ = write(masterFD, ptr, buffer.count)
        }
    }

    // MARK: - Mouse

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    // MARK: - Resize

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updatePTYSize()
    }

    func updatePTYSize() {
        guard masterFD >= 0 else { return }
        let cols = max(1, UInt16(bounds.width / 7.8))
        let rows = max(1, UInt16(bounds.height / 16))

        var winSize = winsize()
        winSize.ws_col = cols
        winSize.ws_row = rows
        winSize.ws_xpixel = UInt16(bounds.width)
        winSize.ws_ypixel = UInt16(bounds.height)

        _ = ioctl(masterFD, TIOCSWINSZ, &winSize)
    }

    // MARK: - Copy/Paste

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if modifiers == .command {
            switch event.charactersIgnoringModifiers {
            case "c":
                if let selectedRange = textView.selectedRanges.first {
                    let range = selectedRange.rangeValue
                    if range.length > 0 {
                        let selected = (textStorage.string as NSString).substring(with: range)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(selected, forType: .string)
                        return true
                    }
                }
            case "v":
                if let str = NSPasteboard.general.string(forType: .string) {
                    writeToPTY(str)
                    return true
                }
            case "a":
                textView.selectAll(nil)
                return true
            default:
                break
            }
        }

        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - TerminalTextView

/// NSTextView subclass that forwards keyboard input to the PTY
/// while preserving mouse-based text selection.
private final class TerminalTextView: NSTextView {
    var onKeyDown: ((NSEvent) -> Void)?

    override func keyDown(with event: NSEvent) {
        if let handler = onKeyDown {
            handler(event)
        } else {
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Let the parent PTYTerminalView handle Cmd+C/V/A
        if let parent = superview?.superview as? PTYTerminalView {
            return parent.performKeyEquivalent(with: event)
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - WeakSendableRef

/// A weak, Sendable wrapper for passing @MainActor-isolated objects into GCD closures.
/// Access `.value` only from the main queue.
private final class WeakSendableRef<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ value: T) { self.value = value }
}
#endif
