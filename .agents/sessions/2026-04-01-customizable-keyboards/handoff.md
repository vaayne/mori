# Handoff

<!-- Append a new phase section after each phase completes. -->

## Phase 1: Core Model & Defaults

**Status:** complete

**Tasks completed:**
- 1.1: Created `KeyBinding`, `Shortcut`, `KeyModifiers`, `KeyBindingCategory`, `ConflictResult` types in MoriCore
- 1.2: Created `KeyBindingStorageProtocol` in the same file
- 1.3: Created `KeyBindingDefaults` with all 50 default bindings (39 configurable + 11 locked system)
- 1.4: Wrote 75 new test assertions in `KeyBindingTests.swift`, integrated into `main.swift`

**Files changed:**
- `Packages/MoriCore/Sources/MoriCore/Models/KeyBinding.swift` — all types + storage protocol
- `Packages/MoriCore/Sources/MoriCore/Models/KeyBindingDefaults.swift` — full default binding table
- `Packages/MoriCore/Tests/MoriCoreTests/KeyBindingTests.swift` — comprehensive tests
- `Packages/MoriCore/Tests/MoriCoreTests/main.swift` — added `runKeyBindingTests()` call

**Commits:**
- `6297a93` — ✨ feat: add KeyBinding, Shortcut, KeyModifiers, KeyBindingCategory, ConflictResult types and KeyBindingStorageProtocol
- `d496c6e` — ✨ feat: add KeyBindingDefaults with all 50 default key bindings (39 configurable + 11 locked system)
- `3b9b549` — ✅ test: add KeyBinding model and defaults unit tests (75 new assertions)

**Decisions & context for next phase:**
- `KeyModifiers` has static presets (`.cmd`, `.cmdShift`, `.cmdOption`, `.cmdControl`, `.ctrl`, `.ctrlShift`) for ergonomic construction
- Plan said ~35 bindings but the actual table specifies 39 configurable + 11 locked = 50 total
- No AppKit imports — all types are cross-platform (macOS + iOS) compatible
- `KeyBindingStorageProtocol` is minimal (load/save overrides as `[String: KeyBinding]`) — Phase 2 will implement the JSON file-backed version
- `ConflictResult` is `Equatable` for easy testing in Phase 3
- All 678 test assertions pass (603 existing + 75 new)

### Fixes (post-review)
- Fixed `window.toggleSidebar` default from `⌘0` to `⌘B` to match AppDelegate and docs (commit `3d59a05`)
- Added `testKeyBindingDefaultsNoShortcutConflicts` to catch duplicate shortcuts in defaults (commit `3d59a05`)

## Phase 2: Persistence (MoriPersistence)

**Status:** complete

**Tasks completed:**
- 2.1: Created `KeyBindingRepository` implementing `KeyBindingStorageProtocol` in MoriPersistence
- 2.2: Wrote 22 new test assertions in `KeyBindingRepositoryTests.swift`, integrated into `main.swift`

**Files changed:**
- `Packages/MoriPersistence/Sources/MoriPersistence/Repositories/KeyBindingRepository.swift` — sparse JSON file-backed storage
- `Packages/MoriPersistence/Tests/MoriPersistenceTests/KeyBindingRepositoryTests.swift` — 5 test functions, 22 assertions
- `Packages/MoriPersistence/Tests/MoriPersistenceTests/main.swift` — added `runKeyBindingRepositoryTests()` call

**Commits:**
- `d020a24` — ✨ feat: add KeyBindingRepository for sparse JSON persistence
- `2636136` — ✅ test: add KeyBindingRepository persistence tests

**Decisions & context for next phase:**
- `KeyBindingRepository` is a standalone `final class` (not tied to `JSONStore`) — it manages its own `keybindings.json` file
- Thread-safe via `NSLock`, matching `JSONStore` pattern
- Sparse storage: only user-overridden bindings are saved; defaults are NOT persisted
- Missing file → empty dict, corrupt file → empty dict (graceful fallback, no crashes)
- File location is passed at init (caller decides path, e.g. `~/Library/Application Support/Mori/keybindings.json`)
- Uses standard `Codable` encoding (no custom ISO8601 needed since `KeyBinding` has no `Date` fields)
- All 64 MoriPersistence test assertions pass (42 existing + 22 new)

## Phase 3: Store & AppKit Bridging (MoriKeybindings)

**Status:** complete

**Tasks completed:**
- 3.1: Created `Packages/MoriKeybindings/Package.swift` (macOS 14+, depends on MoriCore, library + test target)
- 3.2: Created `KeyBindingStore` (`@MainActor @Observable`) with merge, validate, update (with displacement), resetBinding, resetAll
- 3.3: Wired `ConflictResult` into store's `validate()` method (returns `.lockedConflict`, `.configurableConflict`, or `.none`)
- 3.4: Created `KeyBinding+AppKit` extension with `KeyModifiers <-> NSEvent.ModifierFlags` conversion, `Shortcut.matchesEvent(_:)`, and menu properties
- 3.5: Wrote 48 test assertions in `MoriKeybindingsTests` (store lifecycle, conflict detection, displacement, reset, AppKit round-trips)
- 3.6: Added `MoriKeybindings` dependency to root `Package.swift` (both package dependency and Mori target dependency)
- 3.7: Added `test:keybindings` task to `mise.toml` and included in `mise run test`

**Files changed:**
- `Packages/MoriKeybindings/Package.swift` — package manifest
- `Packages/MoriKeybindings/Sources/MoriKeybindings/KeyBindingStore.swift` — observable store with merge/validate/update/reset
- `Packages/MoriKeybindings/Sources/MoriKeybindings/KeyBinding+AppKit.swift` — AppKit bridging extensions
- `Packages/MoriKeybindings/Tests/MoriKeybindingsTests/Assert.swift` — test assertion helpers
- `Packages/MoriKeybindings/Tests/MoriKeybindingsTests/main.swift` — 48 assertions across 21 test functions
- `Package.swift` — added MoriKeybindings dependency
- `mise.toml` — added test:keybindings task

**Commits:**
- `8ef65ce` — ✨ feat: add MoriKeybindings package with KeyBindingStore and AppKit bridging
- `1827404` — ✅ test: add MoriKeybindings unit tests (48 assertions)
- `897784f` — 🔧 chore: wire MoriKeybindings into root Package.swift and mise.toml

**Decisions & context for next phase:**
- `KeyBindingStore` is `@MainActor @Observable` — can be directly observed by SwiftUI views
- `onBindingsChanged` callback is provided for AppDelegate to rebuild menus when bindings change
- `update()` automatically displaces configurable conflicts (sets their shortcut to nil)
- `persist()` uses sparse storage — only saves overrides that differ from defaults
- `MockKeyBindingStorage` pattern in tests can be reused by other test targets
- `Shortcut.matchesEvent(_:)` handles both keyCode-based matching (arrows, tab, return) and character-based matching
- `Shortcut.menuKeyEquivalent` and `menuModifierMask` are ready for NSMenuItem integration
- All 48 MoriKeybindings test assertions pass
- All 678 MoriCore test assertions still pass
