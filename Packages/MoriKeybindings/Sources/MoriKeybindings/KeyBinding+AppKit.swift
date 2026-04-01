import AppKit
import MoriCore

extension KeyModifiers {
    /// Convert to AppKit modifier flags.
    public var nsEventModifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if command { flags.insert(.command) }
        if shift { flags.insert(.shift) }
        if option { flags.insert(.option) }
        if control { flags.insert(.control) }
        return flags
    }

    /// Create from AppKit modifier flags.
    public init(nsEventModifierFlags flags: NSEvent.ModifierFlags) {
        self.init(
            command: flags.contains(.command),
            shift: flags.contains(.shift),
            option: flags.contains(.option),
            control: flags.contains(.control)
        )
    }
}

extension Shortcut {
    /// Check whether this shortcut matches an NSEvent.
    public func matchesEvent(_ event: NSEvent) -> Bool {
        let eventMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard eventMods == modifiers.nsEventModifierFlags else { return false }
        // For keyCodes (arrows, enter, tab), compare keyCode
        if let kc = keyCode {
            return event.keyCode == kc
        }
        // For character keys, compare key string
        return event.charactersIgnoringModifiers?.lowercased() == key.lowercased()
    }

    /// The key equivalent string for use with NSMenuItem.
    public var menuKeyEquivalent: String { key }

    /// The modifier mask for use with NSMenuItem.
    public var menuModifierMask: NSEvent.ModifierFlags { modifiers.nsEventModifierFlags }
}
