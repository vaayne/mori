# Tasks: i18n Support for Mori

## Phase 1: Infrastructure Setup

- [x] 1.1 — Add `defaultLocalization: "en"` to root and all local package Package.swift files (`Package.swift`, `Packages/*/Package.swift`)
- [x] 1.2 — Add `resources: [.process("Resources")]` to MoriUI target (`Packages/MoriUI/Package.swift`)
- [x] 1.3 — Add `resources: [.process("Resources")]` to MoriCLI target (`Package.swift`)
- [x] 1.4 — Add `.process("Resources/Localizable.xcstrings")` to Mori app target resources (`Package.swift`)
- [x] 1.5 — Create `Localizable.xcstrings` for Mori app target (`Sources/Mori/Resources/Localizable.xcstrings`)
- [x] 1.6 — Create `Localizable.xcstrings` for MoriUI package (`Packages/MoriUI/Sources/MoriUI/Resources/Localizable.xcstrings`)
- [x] 1.7 — Create `Localizable.xcstrings` for MoriCLI target (`Sources/MoriCLI/Resources/Localizable.xcstrings`)
- [x] 1.8 — Create `String.localized()` helper extension in each target (`Sources/Mori/App/Localization.swift`, `Packages/MoriUI/Sources/MoriUI/Localization.swift`, `Sources/MoriCLI/Localization.swift`)
- [x] 1.9 — Checkpoint: verify `mise run build` succeeds

## Phase 2: App Target String Wrapping (Representative Subset)

- [x] 2.1 — Wrap menu item strings in `AppDelegate.swift` with `.localized()` (~30 strings)
- [x] 2.2 — Wrap alert/dialog strings in `WorkspaceManager.swift` (~10 strings)
- [x] 2.3 — Wrap notification strings in `NotificationManager.swift` (~5 strings)
- [x] 2.4 — Wrap empty state/error strings in `TerminalAreaViewController.swift` (~5 strings)
- [x] 2.5 — Wrap command palette strings in `CommandPaletteDataSource.swift` and `CommandPaletteController.swift` (~10 strings)
- [x] 2.6 — Add all wrapped strings with `zh-Hans` translations to `Sources/Mori/Resources/Localizable.xcstrings`
- [x] 2.7 — Build and verify strings compile correctly

## Phase 3: MoriUI String Wrapping (Representative Subset)

- [ ] 3.1 — Add `localizedName` to `SettingsCategory` enum, replace `Text(category.rawValue)` with `Text(category.localizedName)` (~8 strings)
- [ ] 3.2 — Wrap section headers and non-literal settings labels in `GhosttySettingsView.swift` (~10 strings)
- [ ] 3.3 — Wrap sidebar labels/help text in `ProjectRailView.swift`, `WorktreeSidebarView.swift` (~10 strings)
- [ ] 3.4 — Wrap status/badge labels in `WorktreeRowView.swift`, `WindowRowView.swift` (~10 strings)
- [ ] 3.5 — Add all wrapped strings with `zh-Hans` translations to MoriUI's `Localizable.xcstrings`
- [ ] 3.6 — Build and verify strings compile correctly

## Phase 4: CLI + Docs + CLAUDE.md

- [ ] 4.1 — Wrap CLI strings in `MoriCLI.swift` with `String(localized:bundle:.module)` (~15 strings)
- [ ] 4.2 — Add `zh-Hans` translations in MoriCLI's `Localizable.xcstrings`
- [ ] 4.3 — Rename `README.zh.md` → `README.zh-Hans.md`, update link in `README.md`
- [ ] 4.4 — Create stub Chinese doc files: `docs/keymaps.zh-Hans.md`, `docs/agent-hooks.zh-Hans.md`, `CHANGELOG.zh-Hans.md`
- [ ] 4.5 — Update CLAUDE.md with i18n conventions section
- [ ] 4.6 — Run full test suite (`mise run test`)
- [ ] 4.7 — Build smoke test: verify app launches under zh-Hans locale
