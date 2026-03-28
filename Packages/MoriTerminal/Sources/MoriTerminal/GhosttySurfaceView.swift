#if os(macOS)
import AppKit
import Carbon
import GhosttyKit

private enum GhosttyInputHelpers {
    static func eventModifierFlags(mods: ghostty_input_mods_e) -> NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags(rawValue: 0)
        if mods.rawValue & GHOSTTY_MODS_SHIFT.rawValue != 0 { flags.insert(.shift) }
        if mods.rawValue & GHOSTTY_MODS_CTRL.rawValue != 0 { flags.insert(.control) }
        if mods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0 { flags.insert(.option) }
        if mods.rawValue & GHOSTTY_MODS_SUPER.rawValue != 0 { flags.insert(.command) }
        return flags
    }

    static var keyboardLayoutID: String? {
        if let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
           let sourceID = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            return unsafeBitCast(sourceID, to: CFString.self) as String
        }

        return nil
    }
}

private extension NSEvent {
    var ghosttyCharacters: String? {
        guard let characters else { return nil }

        if characters.count == 1,
           let scalar = characters.unicodeScalars.first {
            if scalar.value < 0x20 {
                // Strip only Control here. Ghostty handles Ctrl encoding itself,
                // but other modifiers such as Option may still be required to
                // recover the translated text for composed input paths.
                return self.characters(byApplyingModifiers: modifierFlags.subtracting(.control))
            }

            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
                return nil
            }
        }

        return characters
    }

    var hasSingleControlCharacter: Bool {
        guard let characters,
              characters.count == 1,
              let scalar = characters.unicodeScalars.first else {
            return false
        }

        return scalar.value < 0x20
    }
}

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
        guard let surface = ghosttySurface else {
            interpretKeyEvents([event])
            return
        }

        let translatedMods = GhosttyInputHelpers.eventModifierFlags(
            mods: ghostty_surface_key_translation_mods(surface, Self.ghosttyMods(event.modifierFlags))
        )
        var translationMods = event.modifierFlags
        for flag in [NSEvent.ModifierFlags.shift, .control, .option, .command] {
            if translatedMods.contains(flag) {
                translationMods.insert(flag)
            } else {
                translationMods.remove(flag)
            }
        }

        let translationEvent: NSEvent
        if translationMods == event.modifierFlags {
            translationEvent = event
        } else {
            translationEvent = NSEvent.keyEvent(
                with: event.type,
                location: event.locationInWindow,
                modifierFlags: translationMods,
                timestamp: event.timestamp,
                windowNumber: event.windowNumber,
                context: nil,
                characters: event.characters(byApplyingModifiers: translationMods) ?? "",
                charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                isARepeat: event.isARepeat,
                keyCode: event.keyCode
            ) ?? event
        }

        let action: ghostty_input_action_e = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }

        // Track whether we had marked text (IME preedit) before this event.
        let markedTextBefore = markedTextStorage.length > 0
        let keyboardLayoutBefore: String? = if !markedTextBefore {
            GhosttyInputHelpers.keyboardLayoutID
        } else {
            nil
        }

        interpretKeyEvents([translationEvent])

        if !markedTextBefore && keyboardLayoutBefore != GhosttyInputHelpers.keyboardLayoutID {
            return
        }

        // Sync preedit state after interpretKeyEvents (which may have called
        // setMarkedText or unmarkText). This matches the official Ghostty pattern.
        syncPreedit(clearIfNeeded: markedTextBefore)

        if let list = keyTextAccumulator, !list.isEmpty {
            // Composed text from IME — these are final, not composing.
            for text in list {
                _ = sendKeyEvent(action, event: event, translationEvent: translationEvent, text: text)
            }
        } else {
            let composing = markedTextStorage.length > 0 || markedTextBefore
            let text: String? = composing || !event.hasSingleControlCharacter
                ? translationEvent.ghosttyCharacters
                : nil

            // No accumulated text. If we're in preedit or just left preedit,
            // mark as composing so ghostty doesn't process it as real input.
            _ = sendKeyEvent(
                action,
                event: event,
                translationEvent: translationEvent,
                text: text,
                composing: composing
            )
        }
    }

    public override func keyUp(with event: NSEvent) {
        _ = sendKeyEvent(GHOSTTY_ACTION_RELEASE, event: event, text: nil)
    }

    public override func flagsChanged(with event: NSEvent) {
        guard let surface = ghosttySurface else { return }
        guard !hasMarkedText() else { return }

        let mod: UInt32
        switch event.keyCode {
        case 0x39: mod = GHOSTTY_MODS_CAPS.rawValue
        case 0x38, 0x3C: mod = GHOSTTY_MODS_SHIFT.rawValue
        case 0x3B, 0x3E: mod = GHOSTTY_MODS_CTRL.rawValue
        case 0x3A, 0x3D: mod = GHOSTTY_MODS_ALT.rawValue
        case 0x37, 0x36: mod = GHOSTTY_MODS_SUPER.rawValue
        default: return
        }

        let mods = Self.ghosttyMods(event.modifierFlags)
        let action: ghostty_input_action_e = mods.rawValue & mod != 0
            ? GHOSTTY_ACTION_PRESS
            : GHOSTTY_ACTION_RELEASE

        var keyEv = ghostty_input_key_s()
        keyEv.action = action
        keyEv.keycode = UInt32(event.keyCode)
        keyEv.mods = mods
        _ = ghostty_surface_key(surface, keyEv)
    }

    private func sendKeyEvent(
        _ action: ghostty_input_action_e,
        event: NSEvent,
        translationEvent: NSEvent? = nil,
        text: String?,
        composing: Bool = false
    ) -> Bool {
        guard let surface = ghosttySurface else { return false }

        var keyEv = ghostty_input_key_s()
        keyEv.action = action
        keyEv.keycode = UInt32(event.keyCode)
        keyEv.mods = Self.ghosttyMods(event.modifierFlags)
        keyEv.consumed_mods = Self.ghosttyMods(
            (translationEvent?.modifierFlags ?? event.modifierFlags).subtracting([.control, .command])
        )
        keyEv.composing = composing

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
        guard ghosttySurface != nil else { return false }

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

        // Return false for everything else. AppKit's normal flow handles the rest:
        //   1. NSApp tries mainMenu.performKeyEquivalent — Mori menu shortcuts
        //      (⌘T, ⌘W, ⌘D, ⌘G, ⌘], etc.) fire their @objc actions.
        //   2. If the menu doesn't match, the event becomes a regular keyDown
        //      sent to this view (the first responder). Ghostty processes it
        //      and fires actions for its own keybindings (clear_screen, font
        //      size, custom user bindings, etc.) via the onAction callback.
        // This avoids re-entrant menu calls and stale-state issues.
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

}

// MARK: - NSTextInputClient
// Conformance in nonisolated extension to satisfy Swift 6 strict concurrency.
// All methods dispatch to MainActor internally since GhosttySurfaceView is @MainActor.
extension GhosttySurfaceView: @preconcurrency NSTextInputClient {

    public func insertText(_ string: Any, replacementRange: NSRange) {
        let chars: String
        if let attrStr = string as? NSAttributedString {
            chars = attrStr.string
        } else if let str = string as? String {
            chars = str
        } else {
            return
        }

        // Preedit is over when text is inserted.
        unmarkText()

        if var acc = keyTextAccumulator {
            acc.append(chars)
            keyTextAccumulator = acc
        } else if let surface = ghosttySurface {
            ghostty_surface_text(surface, chars, UInt(chars.utf8.count))
        }
    }

    public func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if let attrStr = string as? NSAttributedString {
            markedTextStorage = NSMutableAttributedString(attributedString: attrStr)
        } else if let str = string as? String {
            markedTextStorage = NSMutableAttributedString(string: str)
        }

        // If we're not in a keyDown event, sync preedit immediately.
        // During keyDown, preedit is synced after interpretKeyEvents returns.
        if keyTextAccumulator == nil {
            syncPreedit()
        }
    }

    public func unmarkText() {
        if markedTextStorage.length > 0 {
            markedTextStorage.mutableString.setString("")
            syncPreedit()
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

    /// Sync the preedit state based on markedTextStorage to libghostty.
    private func syncPreedit(clearIfNeeded: Bool = true) {
        guard let surface = ghosttySurface else { return }

        if markedTextStorage.length > 0 {
            let str = markedTextStorage.string
            let len = str.utf8CString.count
            if len > 0 {
                str.withCString { ptr in
                    // Subtract 1 for the null terminator
                    ghostty_surface_preedit(surface, ptr, UInt(len - 1))
                }
            }
        } else if clearIfNeeded {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }
}
#endif
