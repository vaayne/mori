# Handoff

<!-- Append a new phase section after each phase completes. -->

## Phase 1: Infrastructure Setup

**Status:** complete

**Tasks completed:**
- 1.1: Added `defaultLocalization: "en"` to root Package.swift and all 7 local package Package.swift files
- 1.2: Added `resources: [.process("Resources")]` to MoriUI target
- 1.3: Added `resources: [.process("Resources")]` to MoriCLI target
- 1.4: Added `.process("Resources/Localizable.xcstrings")` to Mori app target (alongside existing `.copy()` rules)
- 1.5: Created empty `Localizable.xcstrings` for Mori app target
- 1.6: Created empty `Localizable.xcstrings` for MoriUI package
- 1.7: Created empty `Localizable.xcstrings` for MoriCLI target
- 1.8: Created `String.localized()` helper extension in Mori, MoriUI, and MoriCLI
- 1.9: Verified `mise run build` succeeds (exit code 0, only pre-existing ghostty linker warnings)

**Files changed:**
- `Package.swift` — added `defaultLocalization: "en"`, MoriCLI resources, Mori app `.process()` for xcstrings
- `Packages/MoriCore/Package.swift` — added `defaultLocalization: "en"`
- `Packages/MoriGit/Package.swift` — added `defaultLocalization: "en"`
- `Packages/MoriIPC/Package.swift` — added `defaultLocalization: "en"`
- `Packages/MoriPersistence/Package.swift` — added `defaultLocalization: "en"`
- `Packages/MoriTerminal/Package.swift` — added `defaultLocalization: "en"`
- `Packages/MoriTmux/Package.swift` — added `defaultLocalization: "en"`
- `Packages/MoriUI/Package.swift` — added `defaultLocalization: "en"` and `resources: [.process("Resources")]`
- `Sources/Mori/Resources/Localizable.xcstrings` — new, empty string catalog
- `Packages/MoriUI/Sources/MoriUI/Resources/Localizable.xcstrings` — new, empty string catalog
- `Sources/MoriCLI/Resources/Localizable.xcstrings` — new, empty string catalog
- `Sources/Mori/App/Localization.swift` — new, `String.localized()` helper
- `Packages/MoriUI/Sources/MoriUI/Localization.swift` — new, `String.localized()` helper
- `Sources/MoriCLI/Localization.swift` — new, `String.localized()` helper

**Commits:**
- `fdbf1e7` — 🌐 i18n: add localization infrastructure for Mori, MoriUI, and MoriCLI

**Decisions & context for next phase:**
- Existing `.copy()` rules in Mori app target left untouched (shell scripts need `.copy()` for `Bundle.module.url(forResource:withExtension:)`)
- The `.xcstrings` files have empty `strings` dicts — Phase 2 will populate them with wrapped strings + zh-Hans translations
- `String.localized()` uses `bundle: .module` in all three targets, consistent pattern for all localization
- Build produces only pre-existing ghostty linker warnings (symbol lookup), no new warnings

## Phase 2: App Target String Wrapping

**Status:** complete

**Tasks completed:**
- 2.1: Wrapped 35 menu item strings in AppDelegate.swift (app menu, edit menu, tmux menu, window menu, open panel, settings window title, tmux missing alert, create worktree dialog)
- 2.2: Wrapped 20 alert/dialog strings in WorkspaceManager.swift (create worktree errors, remove worktree confirmation, remove project confirmation, operation error alerts)
- 2.3: Wrapped 9 notification strings in NotificationManager.swift (agent waiting, command error, command finished — titles and bodies, with interpolation variants)
- 2.4: Wrapped 7 strings in TerminalAreaViewController.swift (empty state labels, buttons, error alert)
- 2.5: Wrapped 7 strings in CommandPaletteDataSource.swift (action titles/subtitles) and CommandPaletteController.swift (search placeholder)
- 2.6: Populated Localizable.xcstrings with 86 strings and zh-Hans translations
- 2.7: Build verified — `mise run build` succeeds (exit code 0)

**Files changed:**
- `Sources/Mori/App/AppDelegate.swift` — wrapped menu items, open panel, alerts, settings window title
- `Sources/Mori/App/WorkspaceManager.swift` — wrapped all error alerts, confirmation dialogs
- `Sources/Mori/App/NotificationManager.swift` — wrapped notification titles and bodies
- `Sources/Mori/App/TerminalAreaViewController.swift` — wrapped empty state labels, buttons, error alert
- `Sources/Mori/App/CommandPaletteDataSource.swift` — wrapped action titles and subtitles
- `Sources/Mori/App/CommandPaletteController.swift` — wrapped search field placeholder
- `Sources/Mori/Resources/Localizable.xcstrings` — populated with 86 string entries + zh-Hans translations

**Decisions & context for next phase:**
- Interpolated strings (e.g., `"Remove worktree \"\(name)\"?"`) use `String.LocalizationValue` interpolation; xcstrings keys use `%@` placeholders
- Notification bodies with two interpolation args use positional format specifiers in zh-Hans (`%1$@`, `%2$@`) for word order flexibility
- Apple standard terms used for zh-Hans: 撤销/重做/剪切/拷贝/粘贴/全选/设置/退出/隐藏/窗口/侧栏/全屏/最小化/缩放
- `error.localizedDescription` is NOT wrapped (system-provided, already localized by Foundation)
- Build produces only pre-existing ghostty linker warnings, no new warnings

## Phase 3: MoriUI String Wrapping

**Status:** complete

**Tasks completed:**
- 3.1: Added `localizedName` computed property to `SettingsCategory` enum (7 cases), replaced both `Text(category.rawValue)` usages with `Text(category.localizedName)` in sidebar row and content header
- 3.2: Wrapped 11 `SettingRow` title/description pairs with `.localized()` (Color theme, Background opacity, Font family, Font size, Cursor style, Cursor blink, Option as Alt, Hide while typing, Scroll multiplier, Copy on select, Balance window padding). Wrapped 3 `keybindSectionHeader` call-site strings, 3 `agentCard` name/description pairs, and 1 `Text(model.theme.isEmpty ? "Default" : ...)` ternary
- 3.3: SwiftUI literal strings in `ProjectRailView.swift` and `WorktreeSidebarView.swift` are auto-localized (`.help()`, `.accessibilityLabel()`, `Label()`, `Text("literal")`, `TextField` placeholders). Added zh-Hans translations for all these strings in the xcstrings catalog
- 3.4: Wrapped `Text(window.title.isEmpty ? "Window \(index)" : window.title)` in WindowRowView with `.localized()`. Other strings in WorktreeRowView and WindowRowView are SwiftUI literals (`.help()`, `.accessibilityLabel()`) — auto-localized, with zh-Hans translations added to catalog
- 3.5: Populated MoriUI `Localizable.xcstrings` with 90 string entries and zh-Hans translations
- 3.6: Build verified — `mise run build` succeeds (exit code 0)

**Files changed:**
- `Packages/MoriUI/Sources/MoriUI/GhosttySettingsView.swift` — added `localizedName` to SettingsCategory, wrapped all SettingRow params, keybindSectionHeader params, agentCard params, and Default theme text
- `Packages/MoriUI/Sources/MoriUI/WindowRowView.swift` — wrapped Window fallback title with `.localized()`
- `Packages/MoriUI/Sources/MoriUI/Resources/Localizable.xcstrings` — populated with 90 string entries + zh-Hans translations

**Decisions & context for next phase:**
- SwiftUI literal `Text("string")`, `.help("string")`, `.accessibilityLabel("string")`, `Label("string", ...)` are auto-localized by SwiftUI when the module has `.xcstrings` resources — no explicit `.localized()` needed, but zh-Hans entries must be in the catalog
- `SettingRow` and `agentCard` accept `String` params that flow into `Text(stringVar)` — these are NOT auto-localized, so callers must pass `.localized()` values
- `keybindSectionHeader` similarly accepts a `String` param — callers use `.localized()` at call site
- Interpolated SwiftUI strings like `"Open in \(editor.name)"` use `%@` as the xcstrings key
- Integer interpolations like `"\(worktree.aheadCount) ahead"` use `%lld` as the xcstrings key
- ProjectRailView and WorktreeSidebarView required no code changes — only xcstrings entries for auto-localized literals
- Build produces only pre-existing ghostty linker warnings, no new warnings

## Phase 4: CLI + Docs + CLAUDE.md

**Status:** complete

**Tasks completed:**
- 4.1: Wrapped 16 strings in MoriCLI.swift — all `CommandConfiguration.abstract` strings use `String(localized:bundle:.module)`, all `@Argument`/`@Option` help strings use `ArgumentHelp(String(localized:bundle:.module))`, error output uses `String.localized()` with interpolation
- 4.2: Populated MoriCLI `Localizable.xcstrings` with 16 string entries and zh-Hans translations
- 4.3: Renamed `README.zh.md` to `README.zh-Hans.md` (BCP 47), updated link in `README.md`
- 4.4: Created stub Chinese doc files with translation-pending markers: `docs/keymaps.zh-Hans.md`, `docs/agent-hooks.zh-Hans.md`, `CHANGELOG.zh-Hans.md`
- 4.5: Added "i18n / Localization" section to `CLAUDE.md` (AGENTS.md) with rules for agents
- 4.6: Full test suite run — tmux (200), persistence (47), IPC (39) all pass; MoriCore has 3 pre-existing failures (agentDone badge priority, unrelated to i18n)
- 4.7: Build smoke test passed — `mise run build` succeeds (exit code 0)

**Files changed:**
- `Sources/MoriCLI/MoriCLI.swift` — wrapped all CLI strings with localization
- `Sources/MoriCLI/Resources/Localizable.xcstrings` — populated with 16 string entries + zh-Hans translations
- `README.md` — updated link from `README.zh.md` to `README.zh-Hans.md`
- `README.zh.md` — renamed to `README.zh-Hans.md`
- `CHANGELOG.zh-Hans.md` — new stub with translation-pending marker
- `docs/keymaps.zh-Hans.md` — new stub with translation-pending marker
- `docs/agent-hooks.zh-Hans.md` — new stub with translation-pending marker
- `AGENTS.md` (aka `CLAUDE.md`) — added i18n / Localization conventions section

**Commits:**
- `caf1cb0` — 🌐 i18n: wrap MoriCLI strings and add zh-Hans translations (Phase 4.1-4.2)
- `6ff0de7` — 📝 docs: rename README.zh.md to zh-Hans, add doc stubs and i18n conventions (Phase 4.3-4.5)

**Decisions & notes:**
- ArgumentParser `help:` strings wrapped with `ArgumentHelp(String(localized:bundle:.module))` since `help:` accepts `ArgumentHelp` or `String` — explicit `ArgumentHelp` init needed for `String(localized:)` return type
- Interpolated error message (`"Error: \(message)"`) required extracting to a local variable to avoid type inference ambiguity with `Data(...)` initializer
- 3 pre-existing MoriCore test failures (agentDone badge priority) are unrelated to i18n changes — confirmed by running tests on clean stash
- All doc stubs include both `<!-- Translation pending -->` HTML comment and visible Chinese marker `> 翻译进行中`
