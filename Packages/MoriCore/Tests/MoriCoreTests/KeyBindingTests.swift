import Foundation
import MoriCore

// MARK: - KeyModifiers Tests

func testKeyModifiersDefaultInit() {
    let mods = KeyModifiers()
    assertFalse(mods.command)
    assertFalse(mods.shift)
    assertFalse(mods.option)
    assertFalse(mods.control)
    assertEqual(mods, KeyModifiers.none)
}

func testKeyModifiersStaticPresets() {
    let cmd = KeyModifiers.cmd
    assertTrue(cmd.command)
    assertFalse(cmd.shift)
    assertFalse(cmd.option)
    assertFalse(cmd.control)

    let cmdShift = KeyModifiers.cmdShift
    assertTrue(cmdShift.command)
    assertTrue(cmdShift.shift)
    assertFalse(cmdShift.option)
    assertFalse(cmdShift.control)

    let cmdOption = KeyModifiers.cmdOption
    assertTrue(cmdOption.command)
    assertFalse(cmdOption.shift)
    assertTrue(cmdOption.option)
    assertFalse(cmdOption.control)

    let cmdControl = KeyModifiers.cmdControl
    assertTrue(cmdControl.command)
    assertFalse(cmdControl.shift)
    assertFalse(cmdControl.option)
    assertTrue(cmdControl.control)

    let ctrl = KeyModifiers.ctrl
    assertFalse(ctrl.command)
    assertFalse(ctrl.shift)
    assertFalse(ctrl.option)
    assertTrue(ctrl.control)

    let ctrlShift = KeyModifiers.ctrlShift
    assertFalse(ctrlShift.command)
    assertTrue(ctrlShift.shift)
    assertFalse(ctrlShift.option)
    assertTrue(ctrlShift.control)
}

func testKeyModifiersCodable() {
    let mods = KeyModifiers(command: true, shift: true, option: false, control: true)
    let data = try! JSONEncoder().encode(mods)
    let decoded = try! JSONDecoder().decode(KeyModifiers.self, from: data)
    assertEqual(decoded, mods)
}

func testKeyModifiersHashable() {
    let a = KeyModifiers.cmd
    let b = KeyModifiers.cmd
    let c = KeyModifiers.cmdShift
    assertEqual(a, b)
    assertNotEqual(a, c)

    // Can be used in a Set
    let set: Set<KeyModifiers> = [a, b, c]
    assertEqual(set.count, 2)
}

// MARK: - Shortcut Tests

func testShortcutInit() {
    let shortcut = Shortcut(key: "t", modifiers: .cmd)
    assertEqual(shortcut.key, "t")
    assertNil(shortcut.keyCode)
    assertEqual(shortcut.modifiers, .cmd)
}

func testShortcutWithKeyCode() {
    let shortcut = Shortcut(key: "↑", keyCode: 126, modifiers: .cmdOption)
    assertEqual(shortcut.key, "↑")
    assertEqual(shortcut.keyCode, 126)
    assertEqual(shortcut.modifiers, .cmdOption)
}

func testShortcutCodable() {
    let shortcut = Shortcut(key: "d", keyCode: nil, modifiers: .cmdShift)
    let data = try! JSONEncoder().encode(shortcut)
    let decoded = try! JSONDecoder().decode(Shortcut.self, from: data)
    assertEqual(decoded, shortcut)
}

func testShortcutWithKeyCodeCodable() {
    let shortcut = Shortcut(key: "(tab)", keyCode: 48, modifiers: .ctrl)
    let data = try! JSONEncoder().encode(shortcut)
    let decoded = try! JSONDecoder().decode(Shortcut.self, from: data)
    assertEqual(decoded, shortcut)
    assertEqual(decoded.keyCode, 48)
}

func testShortcutHashable() {
    let a = Shortcut(key: "t", modifiers: .cmd)
    let b = Shortcut(key: "t", modifiers: .cmd)
    let c = Shortcut(key: "t", modifiers: .cmdShift)
    assertEqual(a, b)
    assertNotEqual(a, c)
}

// MARK: - KeyBindingCategory Tests

func testKeyBindingCategoryRawValues() {
    assertEqual(KeyBindingCategory.tabs.rawValue, "tabs")
    assertEqual(KeyBindingCategory.panes.rawValue, "panes")
    assertEqual(KeyBindingCategory.tools.rawValue, "tools")
    assertEqual(KeyBindingCategory.window.rawValue, "window")
    assertEqual(KeyBindingCategory.worktrees.rawValue, "worktrees")
    assertEqual(KeyBindingCategory.commandPalette.rawValue, "commandPalette")
    assertEqual(KeyBindingCategory.settings.rawValue, "settings")
    assertEqual(KeyBindingCategory.other.rawValue, "other")
    assertEqual(KeyBindingCategory.system.rawValue, "system")
}

func testKeyBindingCategoryAllCases() {
    assertEqual(KeyBindingCategory.allCases.count, 9)
}

func testKeyBindingCategoryCodable() {
    for category in KeyBindingCategory.allCases {
        let data = try! JSONEncoder().encode(category)
        let decoded = try! JSONDecoder().decode(KeyBindingCategory.self, from: data)
        assertEqual(decoded, category)
    }
}

// MARK: - KeyBinding Tests

func testKeyBindingInit() {
    let binding = KeyBinding(
        id: "tabs.newTab",
        displayNameKey: "keybinding.tabs.newTab",
        category: .tabs,
        shortcut: Shortcut(key: "t", modifiers: .cmd)
    )
    assertEqual(binding.id, "tabs.newTab")
    assertEqual(binding.displayNameKey, "keybinding.tabs.newTab")
    assertEqual(binding.category, .tabs)
    assertNotNil(binding.shortcut)
    assertEqual(binding.shortcut?.key, "t")
    assertFalse(binding.isLocked)
}

func testKeyBindingLocked() {
    let binding = KeyBinding(
        id: "system.copy",
        displayNameKey: "keybinding.system.copy",
        category: .system,
        shortcut: Shortcut(key: "c", modifiers: .cmd),
        isLocked: true
    )
    assertTrue(binding.isLocked)
    assertEqual(binding.category, .system)
}

func testKeyBindingUnassigned() {
    let binding = KeyBinding(
        id: "custom.action",
        displayNameKey: "keybinding.custom.action",
        category: .other
    )
    assertNil(binding.shortcut)
    assertFalse(binding.isLocked)
}

func testKeyBindingCodable() {
    let binding = KeyBinding(
        id: "panes.navUp",
        displayNameKey: "keybinding.panes.navUp",
        category: .panes,
        shortcut: Shortcut(key: "↑", keyCode: 126, modifiers: .cmdOption)
    )
    let data = try! JSONEncoder().encode(binding)
    let decoded = try! JSONDecoder().decode(KeyBinding.self, from: data)
    assertEqual(decoded, binding)
    assertEqual(decoded.shortcut?.keyCode, 126)
}

func testKeyBindingEquatable() {
    let a = KeyBinding(id: "tabs.newTab", displayNameKey: "New Tab", category: .tabs,
                       shortcut: Shortcut(key: "t", modifiers: .cmd))
    let b = KeyBinding(id: "tabs.newTab", displayNameKey: "New Tab", category: .tabs,
                       shortcut: Shortcut(key: "t", modifiers: .cmd))
    let c = KeyBinding(id: "tabs.newTab", displayNameKey: "New Tab", category: .tabs,
                       shortcut: Shortcut(key: "n", modifiers: .cmd))
    assertEqual(a, b)
    assertNotEqual(a, c)
}

func testKeyBindingIdentifiable() {
    let binding = KeyBinding(id: "tools.lazygit", displayNameKey: "Lazygit", category: .tools,
                             shortcut: Shortcut(key: "g", modifiers: .cmd))
    assertEqual(binding.id, "tools.lazygit")
}

// MARK: - ConflictResult Tests

func testConflictResultNone() {
    let result = ConflictResult.none
    assertEqual(result, .none)
}

func testConflictResultLockedConflict() {
    let locked = KeyBinding(id: "system.copy", displayNameKey: "Copy", category: .system,
                            shortcut: Shortcut(key: "c", modifiers: .cmd), isLocked: true)
    let result = ConflictResult.lockedConflict([locked])
    if case .lockedConflict(let bindings) = result {
        assertEqual(bindings.count, 1)
        assertEqual(bindings[0].id, "system.copy")
    } else {
        assertTrue(false, "Expected lockedConflict")
    }
}

func testConflictResultConfigurableConflict() {
    let existing = KeyBinding(id: "tabs.newTab", displayNameKey: "New Tab", category: .tabs,
                              shortcut: Shortcut(key: "t", modifiers: .cmd))
    let result = ConflictResult.configurableConflict([existing])
    if case .configurableConflict(let bindings) = result {
        assertEqual(bindings.count, 1)
        assertEqual(bindings[0].id, "tabs.newTab")
    } else {
        assertTrue(false, "Expected configurableConflict")
    }
}

func testConflictResultEquatable() {
    assertEqual(ConflictResult.none, ConflictResult.none)

    let binding = KeyBinding(id: "test", displayNameKey: "Test", category: .other)
    assertEqual(ConflictResult.lockedConflict([binding]), ConflictResult.lockedConflict([binding]))
    assertNotEqual(ConflictResult.none, ConflictResult.lockedConflict([binding]))
    assertNotEqual(ConflictResult.lockedConflict([binding]), ConflictResult.configurableConflict([binding]))
}

// MARK: - KeyBindingDefaults Tests

func testKeyBindingDefaultsConfigurableCount() {
    assertEqual(KeyBindingDefaults.configurable.count, 39)
}

func testKeyBindingDefaultsLockedCount() {
    assertEqual(KeyBindingDefaults.locked.count, 11)
}

func testKeyBindingDefaultsAllCount() {
    assertEqual(KeyBindingDefaults.all.count, 50)
}

func testKeyBindingDefaultsUniqueIds() {
    let ids = KeyBindingDefaults.all.map { $0.id }
    let uniqueIds = Set(ids)
    assertEqual(ids.count, uniqueIds.count, "All binding IDs must be unique")
}

func testKeyBindingDefaultsNoShortcutConflicts() {
    let withShortcuts = KeyBindingDefaults.all.compactMap { binding -> (String, Shortcut)? in
        guard let shortcut = binding.shortcut else { return nil }
        return (binding.id, shortcut)
    }
    var seen: [String: String] = [:] // "key+mods" -> first binding ID
    for (id, shortcut) in withShortcuts {
        let fingerprint = "\(shortcut.key)|\(shortcut.modifiers)"
        if let existing = seen[fingerprint] {
            assertTrue(false, "Shortcut conflict: \(id) and \(existing) share \(fingerprint)")
        }
        seen[fingerprint] = id
    }
}

func testKeyBindingDefaultsByIdLookup() {
    let byId = KeyBindingDefaults.byId
    assertEqual(byId.count, 50)

    let newTab = byId["tabs.newTab"]
    assertNotNil(newTab)
    assertEqual(newTab?.shortcut?.key, "t")
    assertEqual(newTab?.shortcut?.modifiers, .cmd)
    assertEqual(newTab?.category, .tabs)
    assertFalse(newTab?.isLocked ?? true)

    let copy = byId["system.copy"]
    assertNotNil(copy)
    assertEqual(copy?.shortcut?.key, "c")
    assertTrue(copy?.isLocked ?? false)
}

func testKeyBindingDefaultsAllConfigurableNotLocked() {
    for binding in KeyBindingDefaults.configurable {
        assertFalse(binding.isLocked, "Configurable binding \(binding.id) should not be locked")
    }
}

func testKeyBindingDefaultsAllLockedAreSystem() {
    for binding in KeyBindingDefaults.locked {
        assertTrue(binding.isLocked, "Locked binding \(binding.id) should be locked")
        assertEqual(binding.category, .system, "Locked binding \(binding.id) should be system category")
    }
}

func testKeyBindingDefaultsAllHaveShortcuts() {
    for binding in KeyBindingDefaults.all {
        assertNotNil(binding.shortcut, "Default binding \(binding.id) should have a shortcut")
    }
}

func testKeyBindingDefaultsArrowKeysHaveKeyCodes() {
    let arrowBindings = ["panes.navUp", "panes.navDown", "panes.navLeft", "panes.navRight",
                         "panes.resizeUp", "panes.resizeDown", "panes.resizeLeft", "panes.resizeRight"]
    let byId = KeyBindingDefaults.byId
    for id in arrowBindings {
        let binding = byId[id]
        assertNotNil(binding, "Missing binding \(id)")
        assertNotNil(binding?.shortcut?.keyCode, "Arrow binding \(id) should have a keyCode")
    }
}

func testKeyBindingDefaultsTabKeysHaveKeyCodes() {
    let byId = KeyBindingDefaults.byId
    let cycleNext = byId["worktrees.cycleNext"]
    assertNotNil(cycleNext?.shortcut?.keyCode)
    assertEqual(cycleNext?.shortcut?.keyCode, 48)

    let cyclePrev = byId["worktrees.cyclePrevious"]
    assertNotNil(cyclePrev?.shortcut?.keyCode)
    assertEqual(cyclePrev?.shortcut?.keyCode, 48)
}

func testKeyBindingDefaultsToggleZoomHasKeyCode() {
    let byId = KeyBindingDefaults.byId
    let zoom = byId["panes.toggleZoom"]
    assertNotNil(zoom?.shortcut?.keyCode)
    assertEqual(zoom?.shortcut?.keyCode, 36)
}

func testKeyBindingDefaultsCategoryCounts() {
    let byCategory = Dictionary(grouping: KeyBindingDefaults.all, by: { $0.category })
    assertEqual(byCategory[.tabs]?.count, 13)
    assertEqual(byCategory[.panes]?.count, 14)
    assertEqual(byCategory[.tools]?.count, 2)
    assertEqual(byCategory[.window]?.count, 2)
    assertEqual(byCategory[.worktrees]?.count, 3)
    assertEqual(byCategory[.commandPalette]?.count, 1)
    assertEqual(byCategory[.settings]?.count, 2)
    assertEqual(byCategory[.other]?.count, 2)
    assertEqual(byCategory[.system]?.count, 11)
}

func testKeyBindingDefaultsSpecificBindings() {
    let byId = KeyBindingDefaults.byId

    // Verify a few specific bindings
    let splitRight = byId["panes.splitRight"]
    assertEqual(splitRight?.shortcut?.key, "d")
    assertEqual(splitRight?.shortcut?.modifiers, .cmd)

    let palette = byId["commandPalette.toggle"]
    assertEqual(palette?.shortcut?.key, "p")
    assertEqual(palette?.shortcut?.modifiers, .cmdShift)

    let quit = byId["system.quit"]
    assertEqual(quit?.shortcut?.key, "q")
    assertEqual(quit?.shortcut?.modifiers, .cmd)
    assertTrue(quit?.isLocked ?? false)
}

// MARK: - KeyBinding Codable Round-Trip for Defaults

func testKeyBindingDefaultsCodableRoundTrip() {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    for binding in KeyBindingDefaults.all {
        let data = try! encoder.encode(binding)
        let decoded = try! decoder.decode(KeyBinding.self, from: data)
        assertEqual(decoded, binding, "Round-trip failed for \(binding.id)")
    }
}

// MARK: - Entry Point

func runKeyBindingTests() {
    print("--- KeyBinding Tests ---")

    testKeyModifiersDefaultInit()
    testKeyModifiersStaticPresets()
    testKeyModifiersCodable()
    testKeyModifiersHashable()

    testShortcutInit()
    testShortcutWithKeyCode()
    testShortcutCodable()
    testShortcutWithKeyCodeCodable()
    testShortcutHashable()

    testKeyBindingCategoryRawValues()
    testKeyBindingCategoryAllCases()
    testKeyBindingCategoryCodable()

    testKeyBindingInit()
    testKeyBindingLocked()
    testKeyBindingUnassigned()
    testKeyBindingCodable()
    testKeyBindingEquatable()
    testKeyBindingIdentifiable()

    testConflictResultNone()
    testConflictResultLockedConflict()
    testConflictResultConfigurableConflict()
    testConflictResultEquatable()

    testKeyBindingDefaultsConfigurableCount()
    testKeyBindingDefaultsLockedCount()
    testKeyBindingDefaultsAllCount()
    testKeyBindingDefaultsUniqueIds()
    testKeyBindingDefaultsNoShortcutConflicts()
    testKeyBindingDefaultsByIdLookup()
    testKeyBindingDefaultsAllConfigurableNotLocked()
    testKeyBindingDefaultsAllLockedAreSystem()
    testKeyBindingDefaultsAllHaveShortcuts()
    testKeyBindingDefaultsArrowKeysHaveKeyCodes()
    testKeyBindingDefaultsTabKeysHaveKeyCodes()
    testKeyBindingDefaultsToggleZoomHasKeyCode()
    testKeyBindingDefaultsCategoryCounts()
    testKeyBindingDefaultsSpecificBindings()
    testKeyBindingDefaultsCodableRoundTrip()
}
