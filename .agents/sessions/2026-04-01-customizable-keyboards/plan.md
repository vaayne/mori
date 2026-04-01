# Plan: Customizable Keyboard Shortcuts

## Overview

Add user-customizable keyboard shortcuts to Mori, allowing users to remap app-level keybindings through the existing Keyboard settings sidebar section. Shortcuts are persisted to a dedicated JSON file and applied at runtime to both menu items and the local key monitor.

### Goals

- Users can view all keyboard shortcuts grouped by category in the existing Keyboard settings section
- Users can modify any non-locked keybinding via an inline shortcut recorder
- Conflict detection warns when two actions share the same shortcut
- Users can reset individual bindings or all bindings to defaults
- Changes take effect immediately without app restart

### Success Criteria

- [ ] All ~35 Mori-owned shortcuts are configurable (including expanded grouped shortcuts)
- [ ] Locked shortcuts (system/responder-chain ones) are displayed but not editable
- [ ] Conflict detection warns but allows override with confirmation
- [ ] Bindings persist across app launches via sparse JSON
- [ ] Existing Keyboard settings sidebar section enhanced with shortcut editing
- [ ] Existing tests still pass; new tests cover model + persistence
- [ ] Ghostty terminal keybindings noted as separate in the UI
- [ ] Both English and Chinese keymaps docs updated

### Out of Scope

- Ghostty terminal-level keybindings (configured via `~/.config/ghostty/config`)
- Multi-key chord sequences (e.g., Ctrl+K Ctrl+C)
- Per-project or per-worktree keybinding profiles
- MoriRemote (iOS) keyboard customization

## Technical Approach

### Current Architecture

Shortcuts are hardcoded in `AppDelegate.swift`:
1. `buildMainMenu()` — `NSMenuItem` with `keyEquivalent` + `keyEquivalentModifierMask`
2. `setupCommandPalette()` — `NSEvent.addLocalMonitorForEvents(.keyDown)` with inline checks
3. Existing read-only display in `KeyboardSettingsContent` within `GhosttySettingsView` (sidebar category `.keyboard`)

The existing `KeybindEntry` struct in `GhosttySettingsView.swift` already lists ~23 Mori shortcuts with IDs like `"m.new-tab"`, `"m.split-right"`, etc. — but currently read-only with some grouped entries (e.g., `"m.tab-1-8"`, `"m.pane-nav"`, `"m.pane-resize"`).

### Package Boundary Design

**Critical constraint**: `MoriCore` supports both macOS and iOS (`platforms: [.macOS(.v14), .iOS(.v17)]`). All AppKit-specific code (`NSEvent.ModifierFlags`, `matchesEvent()`) must stay **out of MoriCore**.

```
MoriCore (platform-neutral, macOS + iOS)
  └── KeyBinding model, KeyModifiers, KeyBindingCategory, KeyBindingDefaults
  └── KeyBindingStorageProtocol (protocol for persistence)

MoriPersistence (macOS) → depends on MoriCore
  └── KeyBindingRepository (implements KeyBindingStorageProtocol)

MoriUI (macOS) → depends on MoriCore
  └── KeyBindingsSettingsView, ShortcutRecorderView

MoriKeybindings (new macOS-only local package) → depends on MoriCore
  └── KeyBindingStore (@MainActor, @Observable)
  └── KeyBinding+AppKit extension (NSEvent matching, ModifierFlags conversion)
  └── MoriKeybindingsTests (executable test target)

Mori app target (macOS) → depends on all including MoriKeybindings
  └── AppDelegate refactor (consumes KeyBindingStore)
```

This avoids the MoriCore↔MoriPersistence cycle and provides a **testable package** for the store + AppKit bridging. `MoriKeybindings` depends on `MoriCore` (model) and accepts `KeyBindingStorageProtocol` for persistence injection. The app target wires `KeyBindingRepository` into `KeyBindingStore` at init time.

### Action ID Granularity

Grouped shortcuts from the current `moriKeybinds` must be expanded into individual stable IDs:

| Current grouped entry | Expanded IDs |
|----------------------|-------------|
| `m.tab-1-8` (⌘1–8) | `tabs.gotoTab1` through `tabs.gotoTab8` (8 bindings) |
| `m.tab-9` (⌘9) | `tabs.gotoLastTab` |
| `m.pane-nav` (⌥⌘↑↓←→) | `panes.navUp`, `panes.navDown`, `panes.navLeft`, `panes.navRight` |
| `m.pane-resize` (⌃⌘↑↓←→) | `panes.resizeUp`, `panes.resizeDown`, `panes.resizeLeft`, `panes.resizeRight` |

Total: ~35 individual bindings, each with a unique stable ID.

### Locked vs Configurable Shortcut Matrix

| Category | Shortcuts | Configurable? | Reason |
|----------|-----------|---------------|--------|
| **Edit** | ⌘Z, ⌘⇧Z, ⌘X, ⌘C, ⌘V, ⌘A | ❌ Locked | AppKit responder chain |
| **App system** | ⌘H (Hide), ⌘⌥H (Hide Others), ⌘Q (Quit), ⌘M (Minimize) | ❌ Locked | macOS standard, system-routed |
| **Window system** | ⌘⌃F (Toggle Fullscreen) | ❌ Locked | Routes via responder chain (`NSWindow.toggleFullScreen`) |
| **Tabs** | ⌘T, ⌘W, ⌘⇧], ⌘⇧[, ⌘1-9 | ✅ Configurable | Mori-owned, targeted to AppDelegate |
| **Panes** | ⌘D, ⌘⇧D, ⌘], ⌘[, ⌥⌘↑↓←→, ⌃⌘↑↓←→, ⌘⇧↩, ⌃⌘= | ✅ Configurable | Mori-owned |
| **Tools** | ⌘G, ⌘E | ✅ Configurable | Mori-owned |
| **Window** | ⌘B (sidebar), ⌘⇧W (close window) | ✅ Configurable | Mori-owned |
| **Worktrees** | ⌘⇧N, ⌃Tab, ⌃⇧Tab | ✅ Configurable | Mori-owned |
| **Command Palette** | ⌘⇧P | ✅ Configurable | Mori-owned |
| **Settings** | ⌘, (settings), ⌘⇧, (reload) | ✅ Configurable | Mori-owned |
| **Other** | ⌘⇧O (open project), ⌘⇧A (agent dashboard) | ✅ Configurable | Mori-owned |

### Unassigned Binding State

A `KeyBinding` can be **unassigned** — meaning the user deliberately cleared its shortcut (or it was displaced by conflict resolution). This is modeled by making the shortcut payload optional:

```swift
struct KeyBinding: Codable, Sendable, Identifiable {
    let id: String
    let displayNameKey: String
    let category: KeyBindingCategory
    var shortcut: Shortcut?  // nil = unassigned
    let isLocked: Bool
}

struct Shortcut: Codable, Sendable, Hashable {
    var key: String
    var keyCode: UInt16?
    var modifiers: KeyModifiers
}
```

When `shortcut` is `nil`:
- **UI**: Shows "—" (dash) in the recorder, with a "Record" button to assign
- **Menu**: No `keyEquivalent` set on the `NSMenuItem` (action still available via menu click)
- **Key monitor**: Skipped during event matching loop
- **Persistence**: Stored as `{"shortcut": null}` in overrides JSON (distinguishes "unassigned" from "use default")

### Conflict Handling Flow

1. User records a new shortcut in `ShortcutRecorderView`
2. View calls `onValidate(binding) -> ConflictResult` which returns:
   - `.none` — no conflicts, safe to save
   - `.lockedConflict([KeyBinding])` — conflicts with locked/system shortcuts → **blocked, cannot assign**
   - `.configurableConflict([KeyBinding])` — conflicts with other configurable shortcuts → warn with option to override
3. If `.lockedConflict`: inline error "This shortcut is reserved by [action name] and cannot be reassigned" — recording is rejected
4. If `.configurableConflict`: inline warning "Conflicts with: [action name]" with "Assign Anyway" / "Cancel"
5. "Assign Anyway": calls `onUpdate(binding)` → store saves new binding, sets conflicting binding's `shortcut = nil` (unassigned)
6. "Cancel": reverts to previous value
7. This ensures locked shortcuts are **always protected** from collision

### Settings UI Integration

The existing `KeyboardSettingsContent` in `GhosttySettingsView.swift` already has a "Mori App" keybindings section. We will:
1. Replace the read-only `keybindRow` for Mori shortcuts with an editable `ShortcutRecorderView`
2. Add per-row reset buttons (visible when overridden)
3. Add "Reset All Mori Shortcuts" button
4. Keep Ghostty defaults and user override sections as-is (those are configured via ghostty config)

The `KeyBindingsSettingsView` is a new pure SwiftUI component in MoriUI that `KeyboardSettingsContent` embeds, replacing the current static list.

### Components

- **`KeyBinding` model** (MoriCore): Codable type — `id`, `displayNameKey`, `category`, `shortcut: Shortcut?` (nil = unassigned), `isLocked`
- **`Shortcut`** (MoriCore): Codable struct — `key: String`, `keyCode: UInt16?`, `modifiers: KeyModifiers`
- **`KeyModifiers`** (MoriCore): Codable struct with `command`/`shift`/`option`/`control` booleans — platform-neutral
- **`KeyBindingCategory`** (MoriCore): Enum for grouping
- **`KeyBindingDefaults`** (MoriCore): Static default registry, ~35 bindings
- **`KeyBindingStorageProtocol`** (MoriCore): Protocol for load/save overrides
- **`KeyBindingRepository`** (MoriPersistence): Implements storage protocol, sparse JSON file
- **`KeyBindingStore`** (MoriKeybindings): `@MainActor @Observable`, conflict detection (locked=blocked, configurable=warn), reset
- **`KeyBinding+AppKit`** (MoriKeybindings): Extension with `matchesEvent(_:)`, `NSEvent.ModifierFlags` conversion, `menuKeyEquivalent`/`menuModifierMask`
- **`ConflictResult`** (MoriCore): Enum — `.none`, `.lockedConflict([KeyBinding])`, `.configurableConflict([KeyBinding])` — in Core so MoriUI can use it
- **`ShortcutRecorderView`** (MoriUI): Key capture component
- **`KeyBindingsSettingsView`** (MoriUI): Grouped editable list with conflict warnings

## Implementation Phases

### Phase 1: Core Model & Defaults (MoriCore)

1. Create `KeyBinding`, `Shortcut`, `KeyModifiers`, `KeyBindingCategory` types (file: `Packages/MoriCore/Sources/MoriCore/Models/KeyBinding.swift`)
   - `Shortcut`: Codable struct with `key: String`, `keyCode: UInt16?`, `modifiers: KeyModifiers`
   - `KeyModifiers`: Codable struct, no AppKit dependency
   - `KeyBinding`: `id: String`, `displayNameKey: String`, `category: KeyBindingCategory`, `shortcut: Shortcut?` (nil = unassigned), `isLocked: Bool`
   - `ConflictResult`: enum — `.none`, `.lockedConflict([KeyBinding])`, `.configurableConflict([KeyBinding])` (in MoriCore so MoriUI can consume it without depending on MoriKeybindings)
2. Create `KeyBindingStorageProtocol` (file: `Packages/MoriCore/Sources/MoriCore/Models/KeyBinding.swift`)
   - `func loadOverrides() -> [String: KeyBinding]`
   - `func saveOverrides(_ overrides: [String: KeyBinding])`
3. Create `KeyBindingDefaults` with all ~35 expanded default bindings (file: `Packages/MoriCore/Sources/MoriCore/Models/KeyBindingDefaults.swift`)
   - Each grouped shortcut expanded to individual IDs
   - Locked bindings marked with `isLocked: true`
4. Write unit tests: no duplicate IDs, no conflicts in defaults, all categories represented (file: `Packages/MoriCore/Tests/MoriCoreTests/KeyBindingTests.swift`, update `main.swift`)

### Phase 2: Persistence (MoriPersistence)

1. Create `KeyBindingRepository` implementing `KeyBindingStorageProtocol` (file: `Packages/MoriPersistence/Sources/MoriPersistence/Repositories/KeyBindingRepository.swift`)
   - Sparse JSON storage: only user-overridden bindings saved to `keybindings.json`
   - Thread-safe with `NSLock` (matching `JSONStore` pattern)
   - Graceful fallback on corrupt/missing file
2. Write persistence tests: round-trip, sparse storage verification, corrupt file handling (file: `Packages/MoriPersistence/Tests/MoriPersistenceTests/KeyBindingRepositoryTests.swift`, update `main.swift`)

### Phase 3: Store & AppKit Bridging (MoriKeybindings package)

Create a new local macOS-only package `Packages/MoriKeybindings/` with its own test target.

1. Create `Packages/MoriKeybindings/Package.swift` — depends on `MoriCore`, macOS 14+, products: library `MoriKeybindings`, executable test target `MoriKeybindingsTests`
2. Create `KeyBindingStore` — `@MainActor @Observable` (file: `Packages/MoriKeybindings/Sources/MoriKeybindings/KeyBindingStore.swift`)
   - Init with `KeyBindingStorageProtocol` + defaults
   - `bindings: [KeyBinding]` — merged defaults + overrides
   - `binding(for id:)`, `update(_:)`, `validate(_:) -> ConflictResult`, `resetBinding(id:)`, `resetAll()`
   - `var onBindingsChanged: (() -> Void)?` callback
   - On update: if displacing a configurable binding, set its `shortcut = nil`
   - On update/reset: compute diff from defaults, persist only overrides (nil shortcut = explicit override)
   - Note: `ConflictResult` lives in MoriCore (see Phase 1 step 1) so MoriUI can consume it without depending on MoriKeybindings
4. Create `KeyBinding+AppKit` extension (file: `Packages/MoriKeybindings/Sources/MoriKeybindings/KeyBinding+AppKit.swift`)
   - `KeyModifiers` ↔ `NSEvent.ModifierFlags` conversion
   - `Shortcut.matchesEvent(_ event: NSEvent) -> Bool` (on Shortcut, not KeyBinding — nil shortcut never matches)
   - `Shortcut.menuKeyEquivalent` / `Shortcut.menuModifierMask` computed properties
5. Write unit tests (file: `Packages/MoriKeybindings/Tests/MoriKeybindingsTests/main.swift`)
   - Store update modifies binding, persists override
   - `validate()` returns `.lockedConflict` when colliding with locked binding
   - `validate()` returns `.configurableConflict` when colliding with configurable binding
   - `validate()` returns `.none` when no collision
   - `update()` with displacement sets conflicting binding's shortcut to nil
   - Reset single binding reverts to default shortcut
   - Reset all reverts all and clears overrides
   - Unassigned binding (nil shortcut) skipped by event matching
   - `KeyModifiers` ↔ `NSEvent.ModifierFlags` round-trips
6. Add `MoriKeybindings` dependency to root `Package.swift` Mori target
7. Add `test:keybindings` task to `mise.toml` and update `mise run test` to include it

### Phase 4: AppDelegate Wiring

1. Add `keyBindingStore` property to `AppDelegate`; initialize in `applicationDidFinishLaunching` with `KeyBindingRepository` injected (file: `Sources/Mori/App/AppDelegate.swift`)
2. Refactor `buildMainMenu()`:
   - For configurable menu items: look up binding from store, apply `shortcut?.menuKeyEquivalent` + `shortcut?.menuModifierMask`
   - If `shortcut` is nil (unassigned): set `keyEquivalent = ""` (menu item still clickable, just no shortcut shown)
   - Keep `[String: NSMenuItem]` dictionary mapping action IDs to menu items
   - Locked items stay hardcoded
3. Refactor key monitor in `setupCommandPalette()`:
   - Replace inline if/switch chain with loop: `for binding in keyBindingStore.bindings where !binding.isLocked, let shortcut = binding.shortcut { if shortcut.matchesEvent(event) { dispatch(binding.id); return nil } }`
   - Action dispatch via `[String: () -> Void]` dictionary mapping IDs to existing `@objc` methods
4. Add `rebuildMenuKeyBindings()`:
   - Called from `keyBindingStore.onBindingsChanged`
   - Updates stored menu items' `keyEquivalent` and `keyEquivalentModifierMask` (or clears them if unassigned)
5. Smoke test: all existing shortcuts work unchanged

### Phase 5: Settings UI (MoriUI + app target)

1. Create `ShortcutRecorderView` (file: `Packages/MoriUI/Sources/MoriUI/ShortcutRecorderView.swift`)
   - Pure SwiftUI, captures key events via `NSEvent.addLocalMonitorForEvents` when recording
   - Displays formatted shortcut string (⌘⇧P style) or "—" if unassigned
   - Callbacks: `onRecord: (Shortcut) -> Void`, `onClear: () -> Void` (to explicitly unassign)
2. Create `KeyBindingsSettingsView` (file: `Packages/MoriUI/Sources/MoriUI/KeyBindingsSettingsView.swift`)
   - Pure data + callbacks: `bindings: [KeyBinding]`, `defaults: [KeyBinding]`, `onValidate: (KeyBinding) -> ConflictResult`, `onUpdate: (KeyBinding) -> Void`, `onReset: (String) -> Void`, `onResetAll: () -> Void`
   - Grouped by category, each row: name | `ShortcutRecorderView` | reset button (visible if differs from default)
   - `.lockedConflict`: inline error, recording rejected
   - `.configurableConflict`: inline warning with "Assign Anyway" / "Cancel"
   - Locked rows show shortcut but recorder is disabled
   - Unassigned rows show "—" with option to record a new shortcut
3. Integrate into `KeyboardSettingsContent` in `GhosttySettingsView.swift`:
   - Replace the static `moriKeybinds` list with `KeyBindingsSettingsView`
   - Wire callbacks through `SettingsWindowContent` to `KeyBindingStore`
   - Keep Ghostty defaults + user override sections as-is
4. Add localization strings to both `en.lproj` and `zh-Hans.lproj` in MoriUI resources

### Phase 6: Documentation & Polish

1. Update `docs/keymaps.md` — note customization via Settings > Keyboard
2. Update `docs/keymaps.zh-Hans.md` — corresponding Chinese update
3. Update `CHANGELOG.md` — entry under `[Unreleased]`
4. Final build verification: `mise run build:release`

## Testing Strategy

### Unit Tests (MoriCore)
- `KeyBindingDefaults.all()` returns expected count (~35)
- No duplicate IDs in defaults
- No conflicts in default bindings (same key+mods)
- All categories have at least one binding
- Locked bindings include all Edit + system shortcuts

### Unit Tests (MoriPersistence)
- `KeyBindingRepository` round-trips overrides to JSON
- Only overridden bindings appear in saved file (sparse)
- Missing file returns empty overrides
- Corrupt file returns empty overrides (graceful fallback)

### Unit Tests (MoriKeybindings)
- `KeyBindingStore.update()` modifies a binding and persists
- `KeyBindingStore.validate()` returns `.lockedConflict` for locked shortcut collisions
- `KeyBindingStore.validate()` returns `.configurableConflict` for configurable collisions
- `KeyBindingStore.validate()` returns `.none` when no collision
- `KeyBindingStore.update()` with displacement sets conflicting binding's shortcut to nil
- `KeyBindingStore.resetBinding()` reverts to default and removes override
- `KeyBindingStore.resetAll()` reverts all and clears overrides
- Unassigned binding (nil shortcut) skipped by event matching
- `Shortcut.matchesEvent()` correctly matches key + modifiers
- `KeyModifiers` ↔ `NSEvent.ModifierFlags` round-trips correctly

### Manual Integration Tests
- Launch app → all shortcuts work as before (no regression)
- Open Settings > Keyboard → Mori shortcuts shown with recorders
- Record a new shortcut → menu item updates, key works
- Set conflicting shortcut with configurable action → warning shown, "Assign Anyway" works, displaced action shows "—"
- Try to assign a locked shortcut (e.g., ⌘C) to a configurable action → error shown, recording rejected
- Unassign a shortcut → menu shows no key equivalent, action still clickable
- Reset single binding → reverts to default shortcut
- Reset all → reverts all to defaults
- Quit and relaunch → overrides persisted (including unassigned state)
- Locked shortcuts (⌘C, ⌘Q etc.) → recorder disabled, no editing

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Menu item key equivalents don't update dynamically | High | Test `NSMenuItem.keyEquivalent` setter early in Phase 4; fallback: full menu rebuild |
| Shortcut recorder captures system shortcuts (⌘Tab, ⌘Space) | Medium | Filter out known system shortcuts in recorder; only capture app-level events |
| MoriCore iOS build breaks from AppKit imports | High | All AppKit code in MoriKeybindings package (macOS-only); CI builds both platforms |
| Swift 6 sendability for store | Medium | `KeyBindingStore` is `@MainActor @Observable`; repository uses `NSLock` |
| Ghostty keybinding confusion | Medium | Clear UI label: "Terminal shortcuts configured in Ghostty config" |
| Package cycle if store depends on both Core and Persistence | High | Store in MoriKeybindings; protocol in Core, impl in Persistence; app wires them |
| Unassigned binding confusion | Medium | Clear "—" indicator in UI; menu item still clickable; tooltip explains state |

## Open Questions

*All resolved — converted to assumptions:*

- **Assumption**: Edit menu + Quit + Hide + Minimize + Fullscreen are locked (non-configurable)
- **Assumption**: Locked shortcuts act as **reserved conflicts** — users cannot assign them to other actions
- **Assumption**: Ghostty action handler stays as-is (users customize via ghostty config)
- **Assumption**: Settings UI extends existing Keyboard sidebar section (not a new tab)
- **Assumption**: Conflict resolution with configurable bindings allows "Assign Anyway" which unassigns the displaced binding
- **Assumption**: Grouped shortcuts (⌘1-8, directional nav/resize) are expanded to individual configurable bindings
- **Assumption**: Unassigned state (`shortcut = nil`) is first-class — persisted, rendered as "—", skipped in key monitor
- **Assumption**: `KeyBindingStore` + AppKit bridging live in a new `MoriKeybindings` macOS-only package with its own test target

## Review Feedback

### Round 1 (Codex)

7 issues raised, all addressed in revision 2:

1. ✅ **Package cycle** — `KeyBindingStore` moved out of MoriCore; protocol in MoriCore
2. ✅ **AppKit in MoriCore** — All AppKit bridging outside MoriCore
3. ✅ **Grouped shortcut granularity** — Expanded to individual IDs with explicit table
4. ✅ **Settings UI architecture** — Extends existing Keyboard sidebar section, not new tab
5. ✅ **Conflict handling flow** — Separate validate + update with "Assign Anyway" / "Cancel" UX
6. ✅ **Locked shortcut inventory** — Complete matrix added (Edit, Hide, Quit, Minimize, Fullscreen)
7. ✅ **Chinese docs** — Added `docs/keymaps.zh-Hans.md` update to Phase 6

### Round 2 (Codex)

3 issues raised, all addressed in revision 3:

1. ✅ **App-level test target** — Created new `MoriKeybindings` package with dedicated `MoriKeybindingsTests` executable target
2. ✅ **Locked shortcuts as reserved conflicts** — `validate()` now returns `.lockedConflict` (blocked) vs `.configurableConflict` (warn); locked shortcuts cannot be assigned to other actions
3. ✅ **Unassigned binding state** — `shortcut: Shortcut?` (nil = unassigned) with explicit handling in UI ("—"), menu (no key equivalent), key monitor (skipped), and persistence (stored as null)

**Optional feedback also addressed:**
- ⌘0/⌘B sidebar drift — defaults generated from single source of truth (`KeyBindingDefaults`), replacing the static `moriKeybinds` list

### Round 3 (Codex)

3 consistency issues raised, all addressed in revision 4:

1. ✅ **KeyBinding model mismatch** — Phase 1 step 1 now defines `shortcut: Shortcut?` consistently with unassigned-state design
2. ✅ **MoriUI dependency on ConflictResult** — `ConflictResult` moved to MoriCore so MoriUI can consume it without depending on MoriKeybindings
3. ✅ **mise.toml test task** — Task 3.7 now mandatory: add `test:keybindings` to `mise.toml` and include in `mise run test`

## Final Status

**Implementation: COMPLETE** (2026-04-01)

- All 6 phases implemented and reviewed
- 1,100 test assertions passing across 5 packages (678 core + 64 persistence + 48 keybindings + 249 tmux + 61 IPC)
- 50 key bindings (39 configurable + 11 locked system)
- 73 new localization strings (en + zh-Hans)
- Review fixes applied: sidebar shortcut corrected (⌘0 → ⌘B), shortcut conflict test added, event monitor leak prevention
