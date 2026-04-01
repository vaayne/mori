# Tasks: Customizable Keyboard Shortcuts

## Phase 1: Core Model & Defaults

- [x] 1.1 — Create `KeyBinding`, `Shortcut`, `KeyModifiers`, `KeyBindingCategory`, `ConflictResult` types (`Packages/MoriCore/Sources/MoriCore/Models/KeyBinding.swift`)
- [x] 1.2 — Create `KeyBindingStorageProtocol` in same file
- [x] 1.3 — Create `KeyBindingDefaults` with all ~35 expanded default bindings (`Packages/MoriCore/Sources/MoriCore/Models/KeyBindingDefaults.swift`)
- [x] 1.4 — Write unit tests for model and defaults (`Packages/MoriCore/Tests/MoriCoreTests/KeyBindingTests.swift`, update `main.swift`)

## Phase 2: Persistence

- [x] 2.1 — Create `KeyBindingRepository` implementing `KeyBindingStorageProtocol` (`Packages/MoriPersistence/Sources/MoriPersistence/Repositories/KeyBindingRepository.swift`)
- [x] 2.2 — Write persistence tests (`Packages/MoriPersistence/Tests/MoriPersistenceTests/KeyBindingRepositoryTests.swift`, update `main.swift`)

## Phase 3: Store & AppKit Bridging (MoriKeybindings package)

- [x] 3.1 — Create `Packages/MoriKeybindings/Package.swift` with library + test targets
- [x] 3.2 — Create `KeyBindingStore` with validate/update/reset (`Packages/MoriKeybindings/Sources/MoriKeybindings/KeyBindingStore.swift`)
- [x] 3.3 — Wire `ConflictResult` from MoriCore into store's `validate()` method
- [x] 3.4 — Create `KeyBinding+AppKit` extension with event matching + menu helpers (`Packages/MoriKeybindings/Sources/MoriKeybindings/KeyBinding+AppKit.swift`)
- [x] 3.5 — Write unit tests for store + AppKit bridging (`Packages/MoriKeybindings/Tests/MoriKeybindingsTests/main.swift`)
- [x] 3.6 — Add `MoriKeybindings` dependency to root `Package.swift`
- [x] 3.7 — Add `test:keybindings` task to `mise.toml` and include in `mise run test`

## Phase 4: AppDelegate Wiring

- [x] 4.1 — Add `keyBindingStore` to `AppDelegate`, init with `KeyBindingRepository` (`Sources/Mori/App/AppDelegate.swift`)
- [x] 4.2 — Refactor `buildMainMenu()` to read shortcuts from store, handle nil shortcut (`Sources/Mori/App/AppDelegate.swift`)
- [x] 4.3 — Refactor key monitor in `setupCommandPalette()` to use store lookup loop (`Sources/Mori/App/AppDelegate.swift`)
- [x] 4.4 — Add `rebuildMenuKeyBindings()` and wire to `onBindingsChanged` (`Sources/Mori/App/AppDelegate.swift`)
- [x] 4.5 — Smoke test: verify all existing shortcuts work

## Phase 5: Settings UI

- [x] 5.1 — Create `ShortcutRecorderView` with unassigned display + clear action (`Packages/MoriUI/Sources/MoriUI/ShortcutRecorderView.swift`)
- [x] 5.2 — Create `KeyBindingsSettingsView` with ConflictResult handling (`Packages/MoriUI/Sources/MoriUI/KeyBindingsSettingsView.swift`)
- [x] 5.3 — Integrate into `KeyboardSettingsContent` replacing static moriKeybinds list (`Packages/MoriUI/Sources/MoriUI/GhosttySettingsView.swift`)
- [x] 5.4 — Wire through `SettingsWindowContent` to `KeyBindingStore` (`Sources/Mori/App/AppDelegate.swift`)
- [x] 5.5 — Add localization strings (`Packages/MoriUI/Sources/MoriUI/Resources/{en,zh-Hans}.lproj/Localizable.strings`)

## Phase 6: Documentation & Polish

- [x] 6.1 — Update `docs/keymaps.md` with customization instructions
- [x] 6.2 — Update `docs/keymaps.zh-Hans.md` with corresponding Chinese update
- [x] 6.3 — Update `CHANGELOG.md` with entry under `[Unreleased]`
- [x] 6.4 — Final build verification (`mise run test`)
