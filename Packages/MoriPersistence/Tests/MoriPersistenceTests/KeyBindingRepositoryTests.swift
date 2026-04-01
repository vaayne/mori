import Foundation
import MoriCore
import MoriPersistence

// MARK: - KeyBindingRepository Tests

func runKeyBindingRepositoryTests() throws {
    print("--- KeyBindingRepository Tests ---")
    try testKeyBindingRoundTrip()
    try testKeyBindingSparseStorage()
    try testKeyBindingMissingFile()
    try testKeyBindingCorruptFile()
    try testKeyBindingOverwrite()
}

/// Round-trip: save overrides → load overrides → values match.
func testKeyBindingRoundTrip() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("mori-kb-test-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: tmp) }

    let repo = KeyBindingRepository(fileURL: tmp)

    let binding1 = KeyBinding(
        id: "tabs.newTab",
        displayNameKey: "New Tab",
        category: .tabs,
        shortcut: Shortcut(key: "t", modifiers: .cmd)
    )
    let binding2 = KeyBinding(
        id: "panes.splitRight",
        displayNameKey: "Split Right",
        category: .panes,
        shortcut: Shortcut(key: "d", modifiers: .cmd)
    )

    let overrides: [String: KeyBinding] = [
        binding1.id: binding1,
        binding2.id: binding2,
    ]
    repo.saveOverrides(overrides)

    let loaded = repo.loadOverrides()
    assertEqual(loaded.count, 2)
    assertEqual(loaded["tabs.newTab"]?.shortcut?.key, "t")
    assertEqual(loaded["tabs.newTab"]?.shortcut?.modifiers, .cmd)
    assertEqual(loaded["tabs.newTab"]?.category, .tabs)
    assertEqual(loaded["panes.splitRight"]?.shortcut?.key, "d")
    assertEqual(loaded["panes.splitRight"]?.displayNameKey, "Split Right")
}

/// Sparse storage: only overridden bindings appear in saved file.
func testKeyBindingSparseStorage() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("mori-kb-test-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: tmp) }

    let repo = KeyBindingRepository(fileURL: tmp)

    // Save only one override (not all 50 defaults)
    let binding = KeyBinding(
        id: "tools.commandPalette",
        displayNameKey: "Command Palette",
        category: .commandPalette,
        shortcut: Shortcut(key: "p", modifiers: .cmdShift)
    )
    repo.saveOverrides([binding.id: binding])

    // Verify only that one binding is in the file
    let loaded = repo.loadOverrides()
    assertEqual(loaded.count, 1)
    assertEqual(loaded["tools.commandPalette"]?.shortcut?.key, "p")

    // Verify the raw JSON file contains only one entry
    let data = try Data(contentsOf: tmp)
    let raw = try JSONDecoder().decode([String: KeyBinding].self, from: data)
    assertEqual(raw.count, 1)
}

/// Missing file: `loadOverrides()` returns empty dict.
func testKeyBindingMissingFile() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("mori-kb-nonexistent-\(UUID().uuidString).json")
    // Do NOT create the file

    let repo = KeyBindingRepository(fileURL: tmp)
    let loaded = repo.loadOverrides()
    assertEqual(loaded.count, 0)
}

/// Corrupt file: `loadOverrides()` returns empty dict.
func testKeyBindingCorruptFile() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("mori-kb-test-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: tmp) }

    // Write garbage data
    try "not valid json {{{".data(using: .utf8)!.write(to: tmp, options: .atomic)

    let repo = KeyBindingRepository(fileURL: tmp)
    let loaded = repo.loadOverrides()
    assertEqual(loaded.count, 0)
}

/// Overwrite: saving new overrides replaces old ones.
func testKeyBindingOverwrite() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("mori-kb-test-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: tmp) }

    let repo = KeyBindingRepository(fileURL: tmp)

    // Save first set
    let binding1 = KeyBinding(
        id: "tabs.newTab",
        displayNameKey: "New Tab",
        category: .tabs,
        shortcut: Shortcut(key: "t", modifiers: .cmd)
    )
    repo.saveOverrides([binding1.id: binding1])
    assertEqual(repo.loadOverrides().count, 1)

    // Save second set (completely replaces)
    let binding2 = KeyBinding(
        id: "panes.splitRight",
        displayNameKey: "Split Right",
        category: .panes,
        shortcut: Shortcut(key: "d", modifiers: .cmd)
    )
    let binding3 = KeyBinding(
        id: "panes.splitDown",
        displayNameKey: "Split Down",
        category: .panes,
        shortcut: Shortcut(key: "d", modifiers: .cmdShift)
    )
    repo.saveOverrides([binding2.id: binding2, binding3.id: binding3])

    let loaded = repo.loadOverrides()
    assertEqual(loaded.count, 2)
    assertNil(loaded["tabs.newTab"], "Old override should be gone after overwrite")
    assertNotNil(loaded["panes.splitRight"])
    assertNotNil(loaded["panes.splitDown"])
    assertEqual(loaded["panes.splitDown"]?.shortcut?.modifiers, .cmdShift)
}
