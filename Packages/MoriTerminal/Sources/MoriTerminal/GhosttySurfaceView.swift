import AppKit
import GhosttyKit

/// NSView subclass that hosts a ghostty terminal surface.
/// Handles key/mouse event forwarding, IME input, and Retina scaling.
@MainActor
public final class GhosttySurfaceView: NSView {

    /// The ghostty surface bound to this view.
    var ghosttySurface: ghostty_surface_t?

    /// Accumulated text from interpretKeyEvents for IME composition.
    private var keyTextAccumulator: [String]?

    /// Marked text for IME preedit.
    private var markedTextStorage = NSMutableAttributedString()

    /// Track mouse position for mouse events.
    private var trackingArea: NSTrackingArea?

    override init(frame: NSRect) {
        // Use a non-zero initial frame so ghostty's renderer can initialize.
        // Ghostty requires non-zero layer bounds to set up Metal rendering.
        let initialFrame = frame.size == .zero
            ? NSRect(x: 0, y: 0, width: 800, height: 600)
            : frame
        super.init(frame: initialFrame)
        wantsLayer = true
        layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - First Responder

    public override var acceptsFirstResponder: Bool { true }

    public override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if let surface = ghosttySurface {
            ghostty_surface_set_focus(surface, true)
        }
        return result
    }

    public override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if let surface = ghosttySurface {
            ghostty_surface_set_focus(surface, false)
        }
        return result
    }

    // MARK: - Layout

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateContentScale()
        updateTrackingAreas()
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard let surface = ghosttySurface else { return }
        guard newSize.width > 0, newSize.height > 0 else { return }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        ghostty_surface_set_size(
            surface,
            UInt32(newSize.width * scale),
            UInt32(newSize.height * scale)
        )
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentScale()
    }

    private func updateContentScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        layer?.contentsScale = scale
        if let surface = ghosttySurface {
            ghostty_surface_set_content_scale(surface, scale, scale)
        }
    }

    // MARK: - Keyboard Input

    public override func keyDown(with event: NSEvent) {
        guard ghosttySurface != nil else {
            interpretKeyEvents([event])
            return
        }

        let action: ghostty_input_action_e = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }

        interpretKeyEvents([event])

        if let list = keyTextAccumulator, !list.isEmpty {
            for text in list {
                _ = sendKeyEvent(action, event: event, text: text)
            }
        } else {
            _ = sendKeyEvent(action, event: event, text: event.characters)
        }
    }

    public override func keyUp(with event: NSEvent) {
        _ = sendKeyEvent(GHOSTTY_ACTION_RELEASE, event: event, text: nil)
    }

    public override func flagsChanged(with event: NSEvent) {
        guard let surface = ghosttySurface else { return }
        var keyEv = ghostty_input_key_s()
        keyEv.action = GHOSTTY_ACTION_PRESS
        keyEv.keycode = UInt32(event.keyCode)
        keyEv.mods = Self.ghosttyMods(event.modifierFlags)
        _ = ghostty_surface_key(surface, keyEv)
    }

    private func sendKeyEvent(
        _ action: ghostty_input_action_e,
        event: NSEvent,
        text: String?
    ) -> Bool {
        guard let surface = ghosttySurface else { return false }

        var keyEv = ghostty_input_key_s()
        keyEv.action = action
        keyEv.keycode = UInt32(event.keyCode)
        keyEv.mods = Self.ghosttyMods(event.modifierFlags)
        // consumed_mods tells ghostty which modifiers were used by the OS
        // to produce the text (rather than being real modifier keys).
        // On macOS, Option can either produce special chars (consumed) or
        // act as Alt (not consumed). Ghostty handles this via its
        // macos-option-as-alt config. We report all non-action modifiers
        // as potentially consumed and let ghostty decide.
        keyEv.consumed_mods = GHOSTTY_MODS_NONE

        // Unshifted codepoint
        if event.type == .keyDown || event.type == .keyUp {
            if let chars = event.characters(byApplyingModifiers: []),
               let codepoint = chars.unicodeScalars.first {
                keyEv.unshifted_codepoint = codepoint.value
            }
        }

        if let text, !text.isEmpty,
           let first = text.utf8.first, first >= 0x20 {
            return text.withCString { ptr in
                keyEv.text = ptr
                return ghostty_surface_key(surface, keyEv)
            }
        } else {
            return ghostty_surface_key(surface, keyEv)
        }
    }

    // MARK: - Mouse Input

    public override func updateTrackingAreas() {
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        sendMouseButton(event, state: GHOSTTY_MOUSE_PRESS, button: GHOSTTY_MOUSE_LEFT)
    }

    public override func mouseUp(with event: NSEvent) {
        sendMouseButton(event, state: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_LEFT)
    }

    public override func rightMouseDown(with event: NSEvent) {
        sendMouseButton(event, state: GHOSTTY_MOUSE_PRESS, button: GHOSTTY_MOUSE_RIGHT)
    }

    public override func rightMouseUp(with event: NSEvent) {
        sendMouseButton(event, state: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_RIGHT)
    }

    public override func otherMouseDown(with event: NSEvent) {
        sendMouseButton(event, state: GHOSTTY_MOUSE_PRESS, button: GHOSTTY_MOUSE_MIDDLE)
    }

    public override func otherMouseUp(with event: NSEvent) {
        sendMouseButton(event, state: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_MIDDLE)
    }

    public override func mouseMoved(with event: NSEvent) {
        sendMousePos(event)
    }

    public override func mouseDragged(with event: NSEvent) {
        sendMousePos(event)
    }

    public override func rightMouseDragged(with event: NSEvent) {
        sendMousePos(event)
    }

    public override func otherMouseDragged(with event: NSEvent) {
        sendMousePos(event)
    }

    // MARK: - Key Equivalents

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        guard let surface = ghosttySurface else { return false }

        // If the key event matches any item in Mori's menu bar, let AppKit
        // handle it so all app shortcuts work (Cmd+D split, Cmd+Shift+D split
        // down, Cmd+G lazygit, Cmd+, settings, etc.).
        if let mainMenu = NSApp.mainMenu,
           Self.menuContainsKeyEquivalent(mainMenu, event: event) {
            return false
        }

        // Check if ghostty considers this a key binding
        var ghosttyEvent = ghosttyKeyEvent(GHOSTTY_ACTION_PRESS, event: event)
        let text = event.characters ?? ""
        let isBinding = text.withCString { ptr in
            ghosttyEvent.text = ptr
            var flags = ghostty_binding_flags_e(rawValue: 0)
            return ghostty_surface_key_is_binding(surface, ghosttyEvent, &flags)
        }

        // If ghostty recognizes it as a binding, forward to keyDown
        if isBinding {
            keyDown(with: event)
            return true
        }

        // Handle Ctrl+Return (prevent default context menu equivalent)
        if event.modifierFlags.contains(.control),
           event.charactersIgnoringModifiers == "\r" {
            keyDown(with: event)
            return true
        }

        // Handle Ctrl+/ as Ctrl+_ (prevent macOS beep)
        if event.modifierFlags.contains(.control),
           event.modifierFlags.isDisjoint(with: [.shift, .command, .option]),
           event.charactersIgnoringModifiers == "/" {
            keyDown(with: event)
            return true
        }

        // Ignore synthetic events (zero timestamp)
        if event.timestamp == 0 { return false }

        // Let all non-binding events pass through to AppKit
        // (menu shortcuts, system shortcuts, etc.)
        return false
    }

    private func performSurfaceAction(_ action: String) {
        guard let surface = ghosttySurface else { return }
        _ = ghostty_surface_binding_action(surface, action, UInt(action.utf8.count))
    }

    // MARK: - Copy/Paste IBActions

    @objc func copy(_ sender: Any?) {
        performSurfaceAction("copy_to_clipboard")
    }

    @objc func paste(_ sender: Any?) {
        performSurfaceAction("paste_from_clipboard")
    }

    public override func selectAll(_ sender: Any?) {
        performSurfaceAction("select_all")
    }

    public override func scrollWheel(with event: NSEvent) {
        guard let surface = ghosttySurface else { return }
        var scrollMods: ghostty_input_scroll_mods_t = 0
        if event.hasPreciseScrollingDeltas {
            scrollMods |= 1  // precision bit
        }
        if event.momentumPhase != [] {
            // Map momentum phase to scroll mods
            switch event.momentumPhase {
            case .began: scrollMods |= (1 << 1)
            case .stationary: scrollMods |= (2 << 1)
            case .changed: scrollMods |= (3 << 1)
            case .ended: scrollMods |= (4 << 1)
            case .cancelled: scrollMods |= (5 << 1)
            case .mayBegin: scrollMods |= (6 << 1)
            default: break
            }
        }
        ghostty_surface_mouse_scroll(surface, event.scrollingDeltaX, event.scrollingDeltaY, scrollMods)
    }

    private func sendMouseButton(
        _ event: NSEvent,
        state: ghostty_input_mouse_state_e,
        button: ghostty_input_mouse_button_e
    ) {
        guard let surface = ghosttySurface else { return }
        let mods = Self.ghosttyMods(event.modifierFlags)
        _ = ghostty_surface_mouse_button(surface, state, button, mods)
    }

    private func sendMousePos(_ event: NSEvent) {
        guard let surface = ghosttySurface else { return }
        let pos = convert(event.locationInWindow, from: nil)
        // Ghostty expects top-left origin
        let y = bounds.height - pos.y
        let mods = Self.ghosttyMods(event.modifierFlags)
        ghostty_surface_mouse_pos(surface, pos.x, y, mods)
    }

    // MARK: - Key Event Helpers

    /// Build a ghostty_input_key_s from an NSEvent without sending it.
    private func ghosttyKeyEvent(
        _ action: ghostty_input_action_e,
        event: NSEvent
    ) -> ghostty_input_key_s {
        var keyEv = ghostty_input_key_s()
        keyEv.action = action
        keyEv.keycode = UInt32(event.keyCode)
        keyEv.mods = Self.ghosttyMods(event.modifierFlags)
        keyEv.consumed_mods = GHOSTTY_MODS_NONE
        keyEv.text = nil
        keyEv.composing = false

        if event.type == .keyDown || event.type == .keyUp {
            if let chars = event.characters(byApplyingModifiers: []),
               let codepoint = chars.unicodeScalars.first {
                keyEv.unshifted_codepoint = codepoint.value
            }
        }

        return keyEv
    }

    // MARK: - Modifier Helpers

    static func ghosttyMods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var mods = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }
        return ghostty_input_mods_e(rawValue: mods)
    }

    // MARK: - Menu Key Equivalent Check

    /// Recursively check if any menu item in the hierarchy matches the event's
    /// key equivalent and modifier mask. Used to let Mori menu shortcuts take
    /// priority over ghostty keybindings.
    private static func menuContainsKeyEquivalent(_ menu: NSMenu, event: NSEvent) -> Bool {
        let eventMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let eventChars = event.charactersIgnoringModifiers ?? ""
        guard !eventChars.isEmpty else { return false }

        for item in menu.items {
            if !item.keyEquivalent.isEmpty,
               item.keyEquivalent == eventChars,
               item.keyEquivalentModifierMask == eventMods {
                return true
            }
            if let submenu = item.submenu,
               menuContainsKeyEquivalent(submenu, event: event) {
                return true
            }
        }
        return false
    }
}

// MARK: - NSTextInputClient
// Conformance in nonisolated extension to satisfy Swift 6 strict concurrency.
// All methods dispatch to MainActor internally since GhosttySurfaceView is @MainActor.
extension GhosttySurfaceView: @preconcurrency NSTextInputClient {

    public func insertText(_ string: Any, replacementRange: NSRange) {
        guard let str = string as? String else { return }
        if keyTextAccumulator != nil {
            keyTextAccumulator?.append(str)
        } else if let surface = ghosttySurface {
            ghostty_surface_text(surface, str, UInt(str.utf8.count))
        }
    }

    public func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if let attrStr = string as? NSAttributedString {
            markedTextStorage = NSMutableAttributedString(attributedString: attrStr)
        } else if let str = string as? String {
            markedTextStorage = NSMutableAttributedString(string: str)
        }

        if let surface = ghosttySurface {
            let text = markedTextStorage.string
            ghostty_surface_preedit(surface, text, UInt(text.utf8.count))
        }
    }

    public func unmarkText() {
        markedTextStorage = NSMutableAttributedString()
        if let surface = ghosttySurface {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }

    public func selectedRange() -> NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    public func markedRange() -> NSRange {
        if markedTextStorage.length > 0 {
            return NSRange(location: 0, length: markedTextStorage.length)
        }
        return NSRange(location: NSNotFound, length: 0)
    }

    public func hasMarkedText() -> Bool {
        markedTextStorage.length > 0
    }

    public func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        nil
    }

    public func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    public func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let surface = ghosttySurface else { return .zero }
        var x: Double = 0, y: Double = 0, w: Double = 0, h: Double = 0
        ghostty_surface_ime_point(surface, &x, &y, &w, &h)
        let screenPoint = window?.convertToScreen(NSRect(x: x, y: bounds.height - y - h, width: w, height: h)) ?? .zero
        return screenPoint
    }

    public func characterIndex(for point: NSPoint) -> Int {
        0
    }

    public override func doCommand(by selector: Selector) {
        // Let the input system handle standard commands
    }
}
