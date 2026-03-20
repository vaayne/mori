# Plan: i18n Support for Mori

## Overview

Add internationalization infrastructure to Mori, supporting English (base) and Simplified Chinese (`zh-Hans`) with an extensible architecture for future languages. Covers the GUI app, CLI tool, and all user-facing documentation.

**Scope**: Architecture setup + representative string wrapping patterns. Full translation of all ~430 strings is a follow-up task delegated to subagents.

### Goals

- Establish `.xcstrings` String Catalog infrastructure across all targets with user-facing strings
- Create a clear, repeatable pattern for localizing strings in both AppKit and SwiftUI code
- Wrap a representative subset of strings to validate the pattern works end-to-end
- Set up parallel doc translation structure for all user-facing docs
- Add i18n rules to CLAUDE.md so agents maintain localization going forward

### Success Criteria

- [ ] `defaultLocalization: "en"` set in Package.swift files for targets with resources
- [ ] `.xcstrings` String Catalogs created for: Mori app, MoriUI, MoriCLI
- [ ] `resources: [.process("Resources")]` added to MoriUI and MoriCLI targets
- [ ] Representative strings wrapped with `String(localized:bundle:.module)` and appear in catalogs
- [ ] `zh-Hans` translations present for the representative subset
- [ ] App builds and runs with both English and Chinese locale
- [ ] CLI `mori --help` output localizable
- [ ] Doc translation structure established for all user-facing docs
- [ ] CLAUDE.md updated with i18n conventions
- [ ] All existing tests pass

### Out of Scope

- Full translation of all ~430 strings (follow-up subagent task)
- Right-to-left (RTL) language support
- Locale-specific date/number formatting (already handled by Foundation)
- Pluralization rules (no plural strings identified in current UI)
- Translation management tooling (Crowdin, Lokalise, etc.)

## Technical Approach

### String Catalogs (`.xcstrings`)

Each target with user-facing strings gets its own `Localizable.xcstrings` in its `Resources/` directory:

| Target | Location | String Count |
|--------|----------|-------------|
| Mori (app) | `Sources/Mori/Resources/Localizable.xcstrings` | ~234 |
| MoriUI | `Packages/MoriUI/Sources/MoriUI/Resources/Localizable.xcstrings` | ~199 |
| MoriCLI | `Sources/MoriCLI/Resources/Localizable.xcstrings` | ~15 |

Minimal `.xcstrings` JSON template:

```json
{
  "sourceLanguage": "en",
  "version": "1.0",
  "strings": {
    "New Tab": {
      "localizations": {
        "zh-Hans": {
          "stringUnit": {
            "state": "translated",
            "value": "新建标签页"
          }
        }
      }
    }
  }
}
```

English is the source language — `en` values are inferred from the key itself (no explicit `en` `stringUnit` needed unless the key differs from the display text). The `zh-Hans` entries provide translations.

Resources must use `.process("Resources")` (not `.copy`) so the Swift build system compiles `.xcstrings` into `.lproj` bundles.

### Bundle Resolution (Critical)

**All targets** must use `bundle: .module` explicitly with `String(localized:)`:

- **Mori app** (`executableTarget`): `Bundle.main` points to the process itself, NOT the SPM resource bundle. Resources live in `Mori_Mori.bundle`, accessible via `Bundle.module`.
- **MoriCLI** (`executableTarget`): Same issue — must use `Bundle.module`.
- **MoriUI** (library target): Resources live in `MoriUI_MoriUI.bundle`. Explicit `String(localized:bundle:.module)` required for all non-literal `Text()` contexts.

**Exception**: SwiftUI `Text("literal")` in a module with resources auto-resolves `Bundle.module` — no explicit bundle needed for literal string `Text` views in MoriUI.

To reduce boilerplate, each target with localized strings gets a small helper:

```swift
// In each target (Mori, MoriUI, MoriCLI)
extension String {
    /// Localized string from this module's bundle.
    static func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}
```

Usage: `item.title = .localized("New Tab")`

### String Wrapping Strategy

**SwiftUI (MoriUI)**:
```swift
// Text with literal — auto-localized, no change needed
Text("Settings")  // ✓ auto-extracted by SwiftUI

// Computed strings — must use explicit localization
// BAD: Text(category.rawValue)  — rawValue is String, NOT localized
// GOOD: Text(category.localizedName)
// where: var localizedName: String { .localized("Theme") }

// Non-Text contexts
let title: String = .localized("Create Worktree")
```

**Enum display names**: Enums like `SettingsCategory` that use `rawValue` for display must get a `localizedName` computed property using `.localized()` instead of relying on `rawValue`.

**AppKit (Mori app)**:
```swift
item.title = .localized("New Tab")
alert.messageText = .localized("tmux not found")
```

**CLI (MoriCLI)**: Use manual `String(localized:bundle:.module)` wrapping for ArgumentParser `abstract`/`discussion`/`help` strings. ArgumentParser's built-in `LocalizableCommand` protocol (v1.3+) exists but adds complexity for minimal benefit in a CLI with ~15 strings — manual wrapping keeps the approach consistent across all targets. Note: localization resolves at process launch time (locale is fixed for CLI lifetime), which is acceptable.

```swift
struct MoriCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: String(localized: "Mori CLI — workspace terminal manager", bundle: .module)
    )
}
```

### Docs Structure

Follow the existing `README.zh.md` pattern. Each doc gets a Chinese variant using BCP 47 tag (`zh-Hans`):

```
README.md           → README.zh-Hans.md  (rename existing README.zh.md)
docs/keymaps.md     → docs/keymaps.zh-Hans.md
docs/agent-hooks.md → docs/agent-hooks.zh-Hans.md
CHANGELOG.md        → CHANGELOG.zh-Hans.md
```

## Implementation Phases

### Phase 1: Infrastructure Setup

1. Add `defaultLocalization: "en"` to root `Package.swift` and local package `Package.swift` files that have (or will have) resources: root, MoriUI. Other packages get it as future-proofing (harmless, ensures readiness). (files: `Package.swift`, `Packages/MoriCore/Package.swift`, `Packages/MoriUI/Package.swift`, `Packages/MoriTmux/Package.swift`, `Packages/MoriGit/Package.swift`, `Packages/MoriTerminal/Package.swift`, `Packages/MoriPersistence/Package.swift`, `Packages/MoriIPC/Package.swift`)
2. Add `resources: [.process("Resources")]` to the MoriUI target in `Packages/MoriUI/Package.swift` (files: `Packages/MoriUI/Package.swift`)
3. Add `resources: [.process("Resources")]` to the MoriCLI target in root `Package.swift`, alongside existing Mori target resources (files: `Package.swift`)
4. Add `.process("Resources/Localizable.xcstrings")` to the Mori app target's resources array in root `Package.swift` (alongside existing `.copy()` rules — do NOT change `.copy()` to `.process()` for shell scripts, as that would break `Bundle.module.url(forResource:withExtension:)` used by `AgentHookConfigurator`) (files: `Package.swift`)
5. Create `Localizable.xcstrings` for the Mori app target with `sourceLanguage: "en"` and empty `strings` dict (files: `Sources/Mori/Resources/Localizable.xcstrings`)
6. Create `Localizable.xcstrings` for MoriUI package (files: `Packages/MoriUI/Sources/MoriUI/Resources/Localizable.xcstrings`)
7. Create `Localizable.xcstrings` for MoriCLI target (files: `Sources/MoriCLI/Resources/Localizable.xcstrings`)
8. Create `String.localized()` helper extension in each target (files: `Sources/Mori/App/Localization.swift`, `Packages/MoriUI/Sources/MoriUI/Localization.swift`, `Sources/MoriCLI/Localization.swift`)
9. **Checkpoint**: Verify the project builds cleanly with `mise run build` — hard gate before proceeding

### Phase 2: App Target String Wrapping (Representative Subset)

Wrap a representative subset of strings in the main app target to validate the pattern. Target: menu items + alerts + notifications (~50 strings).

1. Wrap menu item strings in `AppDelegate.swift` with `.localized()` — all main menu, edit menu, tmux menu, window menu items (~30 strings) (files: `Sources/Mori/App/AppDelegate.swift`)
2. Wrap alert/dialog strings in `WorkspaceManager.swift` with `.localized()` — remove/create worktree dialogs (~10 strings) (files: `Sources/Mori/App/WorkspaceManager.swift`)
3. Wrap notification strings in `NotificationManager.swift` with `.localized()` (~5 strings) (files: `Sources/Mori/App/NotificationManager.swift`)
4. Wrap empty state and error strings in `TerminalAreaViewController.swift` (~5 strings) (files: `Sources/Mori/App/TerminalAreaViewController.swift`)
5. Wrap command palette strings in `CommandPaletteDataSource.swift` and `CommandPaletteController.swift` (~10 strings) (files: `Sources/Mori/App/CommandPaletteDataSource.swift`, `Sources/Mori/App/CommandPaletteController.swift`)
6. Add all wrapped strings with `zh-Hans` translations to `Sources/Mori/Resources/Localizable.xcstrings`
7. Build and verify strings compile correctly

### Phase 3: MoriUI String Wrapping (Representative Subset)

Wrap a representative subset in the MoriUI SwiftUI package. Target: settings categories + sidebar labels (~35 strings).

1. Add `localizedName` computed property to `SettingsCategory` enum (and any other enums using `rawValue` for display) using `.localized()` instead of `rawValue`. Update `Text(category.rawValue)` → `Text(category.localizedName)` (~8 strings) (files: `Packages/MoriUI/Sources/MoriUI/GhosttySettingsView.swift`)
2. Wrap section headers and non-literal settings labels in `GhosttySettingsView.swift` (~10 strings) (files: `Packages/MoriUI/Sources/MoriUI/GhosttySettingsView.swift`)
3. Wrap sidebar labels and help text in `ProjectRailView.swift`, `WorktreeSidebarView.swift` (~10 strings) (files: `Packages/MoriUI/Sources/MoriUI/ProjectRailView.swift`, `Packages/MoriUI/Sources/MoriUI/WorktreeSidebarView.swift`)
4. Wrap status/badge labels in `WorktreeRowView.swift`, `WindowRowView.swift`, including computed-string `Text()` calls (~10 strings). Note: `SettingRow` and similar components accept `String` parameters — callers must pass pre-localized strings via `.localized()` at the call site, since `Text(stringVar)` with a `String` variable is verbatim (not auto-localized). (files: `Packages/MoriUI/Sources/MoriUI/WorktreeRowView.swift`, `Packages/MoriUI/Sources/MoriUI/WindowRowView.swift`)
5. Add all wrapped strings with `zh-Hans` translations to MoriUI's `Localizable.xcstrings`
6. Build and verify strings compile correctly

### Phase 4: CLI + Docs + CLAUDE.md

1. Wrap CLI help text and output strings in `MoriCLI.swift` with `String(localized:bundle:.module)` for ArgumentParser static contexts, `.localized()` elsewhere (~15 strings) (files: `Sources/MoriCLI/MoriCLI.swift`)
2. Add `zh-Hans` translations in MoriCLI's `Localizable.xcstrings`
3. Rename `README.zh.md` → `README.zh-Hans.md` for BCP 47 consistency, and update the `<a href="README.zh.md">` link in `README.md` to point to `README.zh-Hans.md` (files: `README.zh-Hans.md`, `README.md`)
4. Create stub Chinese doc files: `docs/keymaps.zh-Hans.md`, `docs/agent-hooks.zh-Hans.md`, `CHANGELOG.zh-Hans.md` with headers and translation-pending markers
5. Update CLAUDE.md with i18n conventions section (file: `CLAUDE.md`)
6. Run full test suite (`mise run test`) to verify nothing is broken
7. Build smoke test: verify app launches without crash under `zh-Hans` locale (`defaults write ... AppleLanguages '(zh-Hans)'`)

## Testing Strategy

- `mise run build` succeeds after each phase (hard gate at Phase 1)
- `mise run test` passes after final phase (all existing tests)
- Validate `.xcstrings` files are valid JSON with `python3 -c "import json; json.load(open('path'))"` after each catalog update
- Build smoke test: launch app with `defaults write com.mori.app AppleLanguages '(zh-Hans)'` and confirm translated menu items appear
- Verify CLI `mori --help` shows localized text when `LANG=zh_Hans.UTF-8`

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| SPM + .xcstrings compatibility issues | High | Test build after Phase 1 (hard gate); fall back to .strings if needed |
| Bundle.module not available without resources declaration | High | Explicitly add `resources: [.process("Resources")]` to all targets with .xcstrings |
| SwiftUI auto-extraction misses computed strings | Medium | Explicitly use `.localized()` for enum rawValues, ternaries, and interpolated strings |
| ArgumentParser static context timing | Low | Locale resolves at process launch — acceptable for CLI |
| Existing README.zh.md rename breaks links | Low | Search for references before renaming |

## Open Questions

(None — all resolved during discovery and review)

## Review Feedback

### Round 1

Reviewer identified 8 issues. All addressed:

1. **[Critical] Bundle.module required everywhere**: Updated all `String(localized:)` to use `bundle: .module`. Added `String.localized()` helper extension pattern to reduce boilerplate.
2. **[Critical] MoriUI explicit bundle**: Clarified that `Text("literal")` auto-resolves but all explicit `String(localized:)` in MoriUI must use `bundle: .module`.
3. **[High] Resources declarations**: Made `resources: [.process("Resources")]` explicit in Phase 1 tasks 2-3 for MoriUI and MoriCLI.
4. **[High] .xcstrings JSON template**: Added minimal template in Technical Approach with `sourceLanguage`, `version`, `strings` structure.
5. **[Medium] SettingsCategory.rawValue**: Added Phase 3 task 1 to create `localizedName` computed property for enums using rawValue for display.
6. **[Medium] ArgumentParser approach**: Documented decision to use manual `String(localized:bundle:.module)` wrapping (consistent, simpler than `LocalizableCommand` for ~15 strings).
7. **[Low] defaultLocalization scope**: Noted that non-resource packages get it as future-proofing.
8. **[Low] Automated smoke test**: Added JSON validation step and locale smoke test to Testing Strategy and Phase 4.

### Round 2

Reviewer identified 3 remaining issues. All addressed:

1. **[High] Mori app target missing `.process()` rule**: Added explicit Phase 1 task 4 to add `.process("Resources/Localizable.xcstrings")` alongside existing `.copy()` rules. Noted not to change `.copy()` rules for shell scripts.
2. **[Medium] README.zh.md link update**: Added sub-task in Phase 4 task 3 to update the href in README.md.
3. **[Low] SettingRow verbatim strings**: Added clarification in Phase 3 task 4 that callers of components accepting `String` params must pass pre-localized strings.

## Final Status

**Complete.** All 4 phases implemented and reviewed on `feature/i18n` branch.

- 29/29 tasks completed
- 192 strings localized (86 app + 90 UI + 16 CLI) with zh-Hans translations
- 3 doc stubs created for future translation
- CLAUDE.md updated with i18n conventions
- Build passes, tests pass (3 pre-existing MoriCore failures unrelated)
- No deviations from plan
