import SwiftUI
import MoriCore

// MARK: - KeyBindingsSettingsView

/// Pure data + callbacks view for editing key bindings grouped by category.
/// Does NOT depend on MoriKeybindings — all data and actions are injected.
public struct KeyBindingsSettingsView: View {
    let bindings: [KeyBinding]
    let defaults: [KeyBinding]
    let onValidate: (KeyBinding) -> ConflictResult
    let onUpdate: (KeyBinding) -> Void
    let onReset: (String) -> Void
    let onResetAll: () -> Void

    public init(
        bindings: [KeyBinding],
        defaults: [KeyBinding],
        onValidate: @escaping (KeyBinding) -> ConflictResult,
        onUpdate: @escaping (KeyBinding) -> Void,
        onReset: @escaping (String) -> Void,
        onResetAll: @escaping () -> Void
    ) {
        self.bindings = bindings
        self.defaults = defaults
        self.onValidate = onValidate
        self.onUpdate = onUpdate
        self.onReset = onReset
        self.onResetAll = onResetAll
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(orderedCategories, id: \.self) { category in
                if let group = groupedBindings[category], !group.isEmpty {
                    CategorySection(
                        category: category,
                        bindings: group,
                        defaults: defaultsById,
                        onValidate: onValidate,
                        onUpdate: onUpdate,
                        onReset: onReset
                    )
                }
            }

            // Reset All button
            HStack {
                Spacer()
                Button {
                    onResetAll()
                } label: {
                    Text(String.localized("Reset All Shortcuts"))
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .padding(.top, 12)
            }
        }
    }

    // MARK: - Helpers

    private var groupedBindings: [KeyBindingCategory: [KeyBinding]] {
        Dictionary(grouping: bindings, by: \.category)
    }

    private var defaultsById: [String: KeyBinding] {
        Dictionary(uniqueKeysWithValues: defaults.map { ($0.id, $0) })
    }

    /// Display categories in a logical order.
    private var orderedCategories: [KeyBindingCategory] {
        [.tabs, .panes, .tools, .window, .worktrees, .commandPalette, .settings, .other, .system]
    }
}

// MARK: - Category Section

private struct CategorySection: View {
    let category: KeyBindingCategory
    let bindings: [KeyBinding]
    let defaults: [String: KeyBinding]
    let onValidate: (KeyBinding) -> ConflictResult
    let onUpdate: (KeyBinding) -> Void
    let onReset: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Category header
            Text(category.localizedName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.03))

            ForEach(bindings) { binding in
                KeyBindingRow(
                    binding: binding,
                    defaultBinding: defaults[binding.id],
                    onValidate: onValidate,
                    onUpdate: onUpdate,
                    onReset: onReset
                )
            }
        }
    }
}

// MARK: - KeyBindingRow

private struct KeyBindingRow: View {
    let binding: KeyBinding
    let defaultBinding: KeyBinding?
    let onValidate: (KeyBinding) -> ConflictResult
    let onUpdate: (KeyBinding) -> Void
    let onReset: (String) -> Void

    @State private var conflictResult: ConflictResult = .none
    @State private var pendingBinding: KeyBinding?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Display name
                Text(binding.displayNameKey.localizedDisplayName)
                    .font(.system(size: 12))
                    .frame(minWidth: 140, alignment: .leading)

                Spacer()

                // Shortcut recorder
                ShortcutRecorderView(
                    shortcut: binding.shortcut,
                    isLocked: binding.isLocked,
                    onRecord: { newShortcut in
                        handleRecord(newShortcut)
                    },
                    onClear: {
                        var updated = binding
                        updated.shortcut = nil
                        onUpdate(updated)
                    }
                )

                // Reset button (fixed width so layout doesn't shift)
                Button {
                    onReset(binding.id)
                    conflictResult = .none
                    pendingBinding = nil
                } label: {
                    Text(String.localized("Reset"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(isOverridden ? 1 : 0)
                .disabled(!isOverridden)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)

            // Conflict messages
            conflictView
        }
    }

    // MARK: - Conflict Handling

    @ViewBuilder
    private var conflictView: some View {
        switch conflictResult {
        case .none:
            EmptyView()

        case .lockedConflict(let conflicts):
            let names = conflicts.map { $0.displayNameKey.localizedDisplayName }.joined(separator: ", ")
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                Text(String(format: .localized("Reserved by %@"), names))
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)

        case .configurableConflict(let conflicts):
            let names = conflicts.map { $0.displayNameKey.localizedDisplayName }.joined(separator: ", ")
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                Text(String(format: .localized("Conflict with %@"), names))
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)

                Button(String.localized("Assign Anyway")) {
                    if let pending = pendingBinding {
                        onUpdate(pending)
                    }
                    conflictResult = .none
                    pendingBinding = nil
                }
                .font(.system(size: 11))
                .buttonStyle(.bordered)

                Button(String.localized("Cancel")) {
                    conflictResult = .none
                    pendingBinding = nil
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Helpers

    private var isOverridden: Bool {
        guard let def = defaultBinding else { return false }
        return binding.shortcut != def.shortcut
    }

    private func handleRecord(_ newShortcut: Shortcut) {
        var proposed = binding
        proposed.shortcut = newShortcut

        let result = onValidate(proposed)
        switch result {
        case .none:
            onUpdate(proposed)
            conflictResult = .none
            pendingBinding = nil

        case .lockedConflict:
            // Show error, reject the recording
            conflictResult = result
            pendingBinding = nil

        case .configurableConflict:
            // Show warning, let user decide
            conflictResult = result
            pendingBinding = proposed
        }
    }
}

// MARK: - Category Localization

extension KeyBindingCategory {
    var localizedName: String {
        switch self {
        case .tabs: return .localized("Tabs")
        case .panes: return .localized("Panes")
        case .tools: return .localized("Tools")
        case .window: return .localized("Window")
        case .worktrees: return .localized("Worktrees")
        case .commandPalette: return .localized("Command Palette")
        case .settings: return .localized("Settings")
        case .other: return .localized("Other")
        case .system: return .localized("System")
        }
    }
}

// MARK: - Display Name Localization

private extension String {
    /// Look up the localized display name for a keybinding displayNameKey.
    var localizedDisplayName: String {
        // displayNameKey format: "keybinding.tabs.newTab" -> look up localization
        .localized(String.LocalizationValue(stringLiteral: self))
    }
}
