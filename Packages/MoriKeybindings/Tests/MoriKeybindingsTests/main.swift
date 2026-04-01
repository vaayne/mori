import AppKit
import Foundation
import MoriCore
import MoriKeybindings

// MARK: - MockKeyBindingStorage

final class MockKeyBindingStorage: KeyBindingStorageProtocol, @unchecked Sendable {
    var stored: [String: KeyBinding] = [:]

    func loadOverrides() -> [String: KeyBinding] {
        stored
    }

    func saveOverrides(_ overrides: [String: KeyBinding]) {
        stored = overrides
    }
}

// MARK: - Test Defaults

let testDefaults: [KeyBinding] = [
    KeyBinding(id: "test.a", displayNameKey: "A", category: .tabs,
               shortcut: Shortcut(key: "a", modifiers: .cmd)),
    KeyBinding(id: "test.b", displayNameKey: "B", category: .tabs,
               shortcut: Shortcut(key: "b", modifiers: .cmd)),
    KeyBinding(id: "test.c", displayNameKey: "C", category: .panes,
               shortcut: Shortcut(key: "c", modifiers: .cmd)),
    KeyBinding(id: "test.locked", displayNameKey: "Locked", category: .system,
               shortcut: Shortcut(key: "z", modifiers: .cmd), isLocked: true),
]

// MARK: - KeyBindingStore Tests

@MainActor
func testStoreInitMergesDefaults() {
    let storage = MockKeyBindingStorage()
    let store = KeyBindingStore(storage: storage, defaults: testDefaults)
    assertEqual(store.bindings.count, 4, "should have 4 bindings from defaults")
    assertEqual(store.binding(for: "test.a")?.shortcut?.key, "a")
}

@MainActor
func testStoreInitWithOverrides() {
    let storage = MockKeyBindingStorage()
    var overridden = testDefaults[0]
    overridden.shortcut = Shortcut(key: "x", modifiers: .cmdShift)
    storage.stored["test.a"] = overridden

    let store = KeyBindingStore(storage: storage, defaults: testDefaults)
    assertEqual(store.binding(for: "test.a")?.shortcut?.key, "x", "override should apply")
    assertEqual(store.binding(for: "test.a")?.shortcut?.modifiers, .cmdShift)
}

@MainActor
func testStoreUpdatePersistsOverride() {
    let storage = MockKeyBindingStorage()
    let store = KeyBindingStore(storage: storage, defaults: testDefaults)

    var updated = testDefaults[0]
    updated.shortcut = Shortcut(key: "x", modifiers: .cmdShift)
    store.update(updated)

    assertEqual(store.binding(for: "test.a")?.shortcut?.key, "x", "binding should be updated")
    assertNotNil(storage.stored["test.a"], "override should be persisted")
    assertEqual(storage.stored["test.a"]?.shortcut?.key, "x")
}

@MainActor
func testStoreUpdateCallsCallback() {
    let storage = MockKeyBindingStorage()
    let store = KeyBindingStore(storage: storage, defaults: testDefaults)

    var callbackCalled = false
    store.onBindingsChanged = { callbackCalled = true }

    var updated = testDefaults[0]
    updated.shortcut = Shortcut(key: "x", modifiers: .cmdShift)
    store.update(updated)

    assertTrue(callbackCalled, "onBindingsChanged should be called")
}

@MainActor
func testValidateNoConflict() {
    let storage = MockKeyBindingStorage()
    let store = KeyBindingStore(storage: storage, defaults: testDefaults)

    let binding = KeyBinding(id: "test.a", displayNameKey: "A", category: .tabs,
                             shortcut: Shortcut(key: "x", modifiers: .cmd))
    let result = store.validate(binding)
    assertEqual(result, .none, "no conflict for unique shortcut")
}

@MainActor
func testValidateNilShortcut() {
    let storage = MockKeyBindingStorage()
    let store = KeyBindingStore(storage: storage, defaults: testDefaults)

    let binding = KeyBinding(id: "test.a", displayNameKey: "A", category: .tabs, shortcut: nil)
    let result = store.validate(binding)
    assertEqual(result, .none, "nil shortcut should not conflict")
}

@MainActor
func testValidateLockedConflict() {
    let storage = MockKeyBindingStorage()
    let store = KeyBindingStore(storage: storage, defaults: testDefaults)

    // Try to assign Cmd+Z which is locked (system.undo equivalent via test.locked)
    let binding = KeyBinding(id: "test.a", displayNameKey: "A", category: .tabs,
                             shortcut: Shortcut(key: "z", modifiers: .cmd))
    let result = store.validate(binding)
    if case .lockedConflict(let conflicts) = result {
        assertEqual(conflicts.count, 1, "should have 1 locked conflict")
        assertEqual(conflicts[0].id, "test.locked")
    } else {
        assertFalse(true, "expected lockedConflict, got \(result)")
    }
}

@MainActor
func testValidateConfigurableConflict() {
    let storage = MockKeyBindingStorage()
    let store = KeyBindingStore(storage: storage, defaults: testDefaults)

    // Try to assign Cmd+B which is already used by test.b
    let binding = KeyBinding(id: "test.a", displayNameKey: "A", category: .tabs,
                             shortcut: Shortcut(key: "b", modifiers: .cmd))
    let result = store.validate(binding)
    if case .configurableConflict(let conflicts) = result {
        assertEqual(conflicts.count, 1, "should have 1 configurable conflict")
        assertEqual(conflicts[0].id, "test.b")
    } else {
        assertFalse(true, "expected configurableConflict, got \(result)")
    }
}

@MainActor
func testUpdateDisplacesConflict() {
    let storage = MockKeyBindingStorage()
    let store = KeyBindingStore(storage: storage, defaults: testDefaults)

    // Assign Cmd+B to test.a — should displace test.b
    var updated = testDefaults[0]
    updated.shortcut = Shortcut(key: "b", modifiers: .cmd)
    store.update(updated)

    assertEqual(store.binding(for: "test.a")?.shortcut?.key, "b", "test.a should have Cmd+B")
    assertNil(store.binding(for: "test.b")?.shortcut, "test.b should be unassigned (displaced)")
}

@MainActor
func testResetSingleBinding() {
    let storage = MockKeyBindingStorage()
    let store = KeyBindingStore(storage: storage, defaults: testDefaults)

    // Override test.a
    var updated = testDefaults[0]
    updated.shortcut = Shortcut(key: "x", modifiers: .cmdShift)
    store.update(updated)
    assertEqual(store.binding(for: "test.a")?.shortcut?.key, "x")

    // Reset it
    store.resetBinding(id: "test.a")
    assertEqual(store.binding(for: "test.a")?.shortcut?.key, "a", "should revert to default")
}

@MainActor
func testResetAllBindings() {
    let storage = MockKeyBindingStorage()
    let store = KeyBindingStore(storage: storage, defaults: testDefaults)

    // Override multiple
    var a = testDefaults[0]
    a.shortcut = Shortcut(key: "x", modifiers: .cmdShift)
    store.update(a)

    var b = testDefaults[1]
    b.shortcut = nil
    store.update(b)

    // Verify overrides applied
    assertEqual(store.binding(for: "test.a")?.shortcut?.key, "x")
    assertNil(store.binding(for: "test.b")?.shortcut)

    // Reset all
    store.resetAll()
    assertEqual(store.binding(for: "test.a")?.shortcut?.key, "a", "test.a should revert")
    assertEqual(store.binding(for: "test.b")?.shortcut?.key, "b", "test.b should revert")
    assertTrue(storage.stored.isEmpty, "persisted overrides should be empty")
}

@MainActor
func testResetCallsCallback() {
    let storage = MockKeyBindingStorage()
    let store = KeyBindingStore(storage: storage, defaults: testDefaults)

    var callCount = 0
    store.onBindingsChanged = { callCount += 1 }

    store.resetBinding(id: "test.a")
    assertEqual(callCount, 1, "resetBinding should call callback")

    store.resetAll()
    assertEqual(callCount, 2, "resetAll should call callback")
}

@MainActor
func testBindingForUnknownId() {
    let storage = MockKeyBindingStorage()
    let store = KeyBindingStore(storage: storage, defaults: testDefaults)
    assertNil(store.binding(for: "nonexistent"), "unknown ID should return nil")
}

@MainActor
func testUnassignedBindingViaOverride() {
    let storage = MockKeyBindingStorage()
    var unassigned = testDefaults[0]
    unassigned.shortcut = nil
    storage.stored["test.a"] = unassigned

    let store = KeyBindingStore(storage: storage, defaults: testDefaults)
    assertNil(store.binding(for: "test.a")?.shortcut, "override with nil shortcut should be unassigned")
}

@MainActor
func testPersistOnlySparseOverrides() {
    let storage = MockKeyBindingStorage()
    let store = KeyBindingStore(storage: storage, defaults: testDefaults)

    // Update test.a to match its default (no-op override)
    store.update(testDefaults[0])
    assertTrue(storage.stored.isEmpty, "no-op update should not persist")

    // Update test.a to something different
    var updated = testDefaults[0]
    updated.shortcut = Shortcut(key: "x", modifiers: .cmdShift)
    store.update(updated)
    assertEqual(storage.stored.count, 1, "should persist only the changed binding")
}

// MARK: - KeyModifiers <-> NSEvent.ModifierFlags Tests

func testKeyModifiersToNSEventFlags() {
    let cmd = KeyModifiers.cmd
    assertEqual(cmd.nsEventModifierFlags, .command)

    let cmdShift = KeyModifiers.cmdShift
    let expected: NSEvent.ModifierFlags = [.command, .shift]
    assertEqual(cmdShift.nsEventModifierFlags, expected)

    let none = KeyModifiers.none
    assertTrue(none.nsEventModifierFlags.isEmpty, "no modifiers should be empty flags")

    let all = KeyModifiers(command: true, shift: true, option: true, control: true)
    let allExpected: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
    assertEqual(all.nsEventModifierFlags, allExpected)
}

func testNSEventFlagsToKeyModifiers() {
    let flags: NSEvent.ModifierFlags = [.command, .shift]
    let mods = KeyModifiers(nsEventModifierFlags: flags)
    assertTrue(mods.command)
    assertTrue(mods.shift)
    assertFalse(mods.option)
    assertFalse(mods.control)
}

func testKeyModifiersRoundTrip() {
    let original = KeyModifiers(command: true, shift: false, option: true, control: false)
    let flags = original.nsEventModifierFlags
    let roundTripped = KeyModifiers(nsEventModifierFlags: flags)
    assertEqual(original, roundTripped, "round-trip should preserve modifiers")
}

func testKeyModifiersRoundTripAll() {
    let presets: [KeyModifiers] = [.none, .cmd, .cmdShift, .cmdOption, .cmdControl, .ctrl, .ctrlShift]
    for preset in presets {
        let flags = preset.nsEventModifierFlags
        let roundTripped = KeyModifiers(nsEventModifierFlags: flags)
        assertEqual(preset, roundTripped, "round-trip should work for preset")
    }
}

// MARK: - Shortcut Menu Properties Tests

func testShortcutMenuKeyEquivalent() {
    let shortcut = Shortcut(key: "t", modifiers: .cmd)
    assertEqual(shortcut.menuKeyEquivalent, "t")
    assertEqual(shortcut.menuModifierMask, .command)
}

func testShortcutMenuModifierMask() {
    let shortcut = Shortcut(key: "d", modifiers: .cmdShift)
    assertEqual(shortcut.menuModifierMask, [.command, .shift])
}

// MARK: - Main

print("=== MoriKeybindings Tests ===")

// Store tests (must run on MainActor)
MainActor.assumeIsolated {
    testStoreInitMergesDefaults()
    testStoreInitWithOverrides()
    testStoreUpdatePersistsOverride()
    testStoreUpdateCallsCallback()
    testValidateNoConflict()
    testValidateNilShortcut()
    testValidateLockedConflict()
    testValidateConfigurableConflict()
    testUpdateDisplacesConflict()
    testResetSingleBinding()
    testResetAllBindings()
    testResetCallsCallback()
    testBindingForUnknownId()
    testUnassignedBindingViaOverride()
    testPersistOnlySparseOverrides()
}

// AppKit extension tests
testKeyModifiersToNSEventFlags()
testNSEventFlagsToKeyModifiers()
testKeyModifiersRoundTrip()
testKeyModifiersRoundTripAll()
testShortcutMenuKeyEquivalent()
testShortcutMenuModifierMask()

printResults()

if failCount > 0 {
    fflush(stdout)
    fatalError("Tests failed")
}
