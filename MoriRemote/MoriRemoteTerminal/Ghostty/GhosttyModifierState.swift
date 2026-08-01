import Foundation

struct GhosttyModifierState: Equatable {
    private(set) var controlArmed = false
    private(set) var altArmed = false

    var isControlArmed: Bool { controlArmed }
    var isAltArmed: Bool { altArmed }

    mutating func toggleControl() { controlArmed.toggle() }
    mutating func toggleAlt() { altArmed.toggle() }
    mutating func clearControl() { controlArmed = false }
    mutating func clearAlt() { altArmed = false }

    mutating func apply(to text: String) -> String {
        guard controlArmed || altArmed else { return text }
        defer {
            controlArmed = false
            altArmed = false
        }
        let controlled = controlArmed ? (Self.controlText(for: text) ?? text) : text
        // Terminal Alt/Meta text is conventionally encoded as an ESC prefix.
        // Key events use the native Alt modifier below instead.
        return altArmed ? "\u{1B}" + controlled : controlled
    }

    mutating func apply(to event: GhosttySurfaceKeyEvent) -> GhosttySurfaceKeyEvent {
        guard controlArmed || altArmed else { return event }
        defer {
            controlArmed = false
            altArmed = false
        }
        var mods = event.mods
        if controlArmed { mods.insert(.ctrl) }
        if altArmed { mods.insert(.alt) }

        return GhosttySurfaceKeyEvent(
            action: event.action,
            keyCode: event.keyCode,
            text: event.text,
            composing: event.composing,
            mods: mods,
            consumedMods: event.consumedMods,
            unshiftedCodepoint: event.unshiftedCodepoint
        )
    }

    static func controlText(for text: String) -> String? {
        guard
            text.count == 1,
            let scalar = text.unicodeScalars.first,
            let translated = controlScalar(for: scalar)
        else {
            return nil
        }

        return String(translated)
    }

    static func controlScalar(for scalar: UnicodeScalar) -> UnicodeScalar? {
        switch scalar.value {
        case 0x41 ... 0x5A:
            return UnicodeScalar(scalar.value - 0x40)
        case 0x61 ... 0x7A:
            return UnicodeScalar(scalar.value - 0x60)
        case 0x20, 0x40:
            return UnicodeScalar(0x00)
        case 0x5B:
            return UnicodeScalar(0x1B)
        case 0x5C:
            return UnicodeScalar(0x1C)
        case 0x5D:
            return UnicodeScalar(0x1D)
        case 0x5E, 0x36:
            return UnicodeScalar(0x1E)
        case 0x5F, 0x2D:
            return UnicodeScalar(0x1F)
        default:
            return nil
        }
    }
}
