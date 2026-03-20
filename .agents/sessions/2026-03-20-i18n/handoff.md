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
