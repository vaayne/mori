import Foundation
import MoriCore

/// Observable store that manages key bindings, merging defaults with user overrides.
@MainActor
@Observable
public final class KeyBindingStore {
    /// The merged list of all bindings (defaults + overrides).
    public private(set) var bindings: [KeyBinding]

    /// User overrides keyed by binding ID.
    private var overrides: [String: KeyBinding]

    /// The storage backend for persisting overrides.
    private let storage: KeyBindingStorageProtocol

    /// The default bindings to merge against.
    private let defaults: [KeyBinding]

    /// Callback invoked whenever bindings change (after update/reset).
    public var onBindingsChanged: (@MainActor () -> Void)?

    public init(storage: KeyBindingStorageProtocol, defaults: [KeyBinding] = KeyBindingDefaults.all) {
        self.storage = storage
        self.defaults = defaults
        self.overrides = storage.loadOverrides()
        self.bindings = Self.merge(defaults: defaults, overrides: storage.loadOverrides())
    }

    // MARK: - Query

    /// Find a binding by its action ID.
    public func binding(for id: String) -> KeyBinding? {
        bindings.first { $0.id == id }
    }

    // MARK: - Validation

    /// Check whether the proposed binding's shortcut conflicts with existing bindings.
    public func validate(_ binding: KeyBinding) -> ConflictResult {
        guard let shortcut = binding.shortcut else {
            return .none
        }

        let conflicts = bindings.filter { existing in
            existing.id != binding.id && existing.shortcut == shortcut
        }

        guard !conflicts.isEmpty else {
            return .none
        }

        let lockedConflicts = conflicts.filter(\.isLocked)
        if !lockedConflicts.isEmpty {
            return .lockedConflict(lockedConflicts)
        }

        return .configurableConflict(conflicts)
    }

    // MARK: - Mutation

    /// Update a binding. Displaces any configurable binding with the same shortcut.
    public func update(_ binding: KeyBinding) {
        // Displace configurable conflicts
        if let shortcut = binding.shortcut {
            let displaced = bindings.filter { existing in
                existing.id != binding.id
                    && !existing.isLocked
                    && existing.shortcut == shortcut
            }
            for var d in displaced {
                d.shortcut = nil
                overrides[d.id] = d
            }
        }

        overrides[binding.id] = binding
        recompute()
        persist()
        onBindingsChanged?()
    }

    /// Reset a single binding to its default shortcut.
    public func resetBinding(id: String) {
        overrides.removeValue(forKey: id)
        recompute()
        persist()
        onBindingsChanged?()
    }

    /// Reset all bindings to defaults, clearing all overrides.
    public func resetAll() {
        overrides.removeAll()
        recompute()
        persist()
        onBindingsChanged?()
    }

    // MARK: - Private

    private func recompute() {
        bindings = Self.merge(defaults: defaults, overrides: overrides)
    }

    private func persist() {
        // Only persist entries that differ from defaults
        let defaultsById = Dictionary(uniqueKeysWithValues: defaults.map { ($0.id, $0) })
        let sparse = overrides.filter { id, binding in
            defaultsById[id] != binding
        }
        storage.saveOverrides(sparse)
    }

    /// Merge defaults with overrides: start with defaults, apply overrides on top by ID.
    static func merge(defaults: [KeyBinding], overrides: [String: KeyBinding]) -> [KeyBinding] {
        defaults.map { defaultBinding in
            if let override = overrides[defaultBinding.id] {
                return override
            }
            return defaultBinding
        }
    }
}
