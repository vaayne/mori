import Foundation

// MARK: - KeyModifiers

/// Modifier key flags for a keyboard shortcut.
public struct KeyModifiers: Codable, Sendable, Hashable {
    public var command: Bool
    public var shift: Bool
    public var option: Bool
    public var control: Bool

    public init(
        command: Bool = false,
        shift: Bool = false,
        option: Bool = false,
        control: Bool = false
    ) {
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }

    /// No modifiers pressed.
    public static let none = KeyModifiers()

    /// Command key only.
    public static let cmd = KeyModifiers(command: true)

    /// Command + Shift.
    public static let cmdShift = KeyModifiers(command: true, shift: true)

    /// Command + Option.
    public static let cmdOption = KeyModifiers(command: true, option: true)

    /// Command + Control.
    public static let cmdControl = KeyModifiers(command: true, control: true)

    /// Control only.
    public static let ctrl = KeyModifiers(control: true)

    /// Control + Shift.
    public static let ctrlShift = KeyModifiers(shift: true, control: true)
}

// MARK: - Shortcut

/// A keyboard shortcut: a key (character or name) plus modifier flags.
public struct Shortcut: Codable, Sendable, Hashable {
    /// The key character or name, e.g. "t", "1", "↑", "(tab)".
    public var key: String

    /// Optional NSEvent keyCode for keys that lack a unique character (arrows, tab, return).
    public var keyCode: UInt16?

    /// Modifier flags.
    public var modifiers: KeyModifiers

    public init(key: String, keyCode: UInt16? = nil, modifiers: KeyModifiers = .none) {
        self.key = key
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

// MARK: - KeyBindingCategory

/// Categories for grouping key bindings in the settings UI.
public enum KeyBindingCategory: String, Codable, Sendable, CaseIterable {
    case projects
    case tabs
    case panes
    case tools
    case window
    case worktrees
    case commandPalette
    case settings
    case other
    case system
}

// MARK: - KeyBinding

/// A single key binding mapping an action ID to a keyboard shortcut.
public struct KeyBinding: Codable, Sendable, Identifiable, Equatable, Hashable {
    /// Stable action identifier, e.g. "tabs.newTab".
    public let id: String

    /// Localization key for the display name.
    public let displayNameKey: String

    /// Category for grouping in settings UI.
    public let category: KeyBindingCategory

    /// The assigned shortcut, or nil if unassigned.
    public var shortcut: Shortcut?

    /// Whether this binding is locked (system/responder-chain shortcuts that cannot be reassigned).
    public let isLocked: Bool

    public init(
        id: String,
        displayNameKey: String,
        category: KeyBindingCategory,
        shortcut: Shortcut? = nil,
        isLocked: Bool = false
    ) {
        self.id = id
        self.displayNameKey = displayNameKey
        self.category = category
        self.shortcut = shortcut
        self.isLocked = isLocked
    }
}

// MARK: - ConflictResult

/// Result of checking a shortcut for conflicts with existing bindings.
public enum ConflictResult: Sendable, Equatable {
    /// No conflict detected.
    case none

    /// Conflicts with one or more locked (system) bindings — cannot be overridden.
    case lockedConflict([KeyBinding])

    /// Conflicts with one or more configurable bindings — user can choose to override.
    case configurableConflict([KeyBinding])
}

// MARK: - KeyBindingStorageProtocol

/// Abstraction for loading and saving user key binding overrides.
public protocol KeyBindingStorageProtocol: Sendable {
    /// Load user overrides. Keys are binding IDs.
    func loadOverrides() -> [String: KeyBinding]

    /// Save user overrides. Keys are binding IDs.
    func saveOverrides(_ overrides: [String: KeyBinding])
}
