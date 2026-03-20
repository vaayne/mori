# AGENTS.md

Guidance for AI coding agents working in this repository.

## Build & Test

```bash
mise run build           # Debug build
mise run build:release   # Release build
mise run dev             # Build + run the app
mise run test            # All tests (parallel across packages)
mise run test:core       # MoriCore tests only
mise run test:persistence # MoriPersistence tests only
mise run test:tmux       # MoriTmux tests only
mise run test:ipc        # MoriIPC tests only
mise run clean           # Remove .build and .derived-data
```

Tests are executable targets (not XCTest), run via `swift run <TestTarget>` from each package directory.

## Key Conventions

- **Swift 6 strict concurrency**: UI code is `@MainActor`, tmux/git use actors
- **macOS 14+ (Sonoma)**: Required for `@Observable` macro
- **AppKit-first**: SwiftUI only for sidebar leaf views, AppKit for terminal and window management
- **SwiftUI views are pure**: Data + callbacks as parameters, no direct AppState dependency
- **No XCTest**: Tests are executable targets with custom `assertEqual`/`assertTrue` helpers

## Release

See [release skill](.agents/skills/release/SKILL.md) for the full release workflow.

## Docs to Keep in Sync

- **`CHANGELOG.md`** — entry under `[Unreleased]` for every user-visible change
- **`AGENTS.md`** — update if build commands or conventions change
- **`README.md`** — update if features, install steps, or usage change

## i18n / Localization

- All new user-facing strings must use `.localized()` — same pattern in app, UI, and CLI
- Add entries to both `en.lproj/Localizable.strings` and `zh-Hans.lproj/Localizable.strings`
- SwiftUI `Text("literal")` is auto-localized; computed strings need explicit `.localized()`
- Do not localize: log messages, internal identifiers, tmux commands
- Keep docs in sync: when updating English docs, note that Chinese counterparts need updating
- String file locations (each target has `en.lproj` + `zh-Hans.lproj`):
  - `Sources/Mori/Resources/` (app target)
  - `Packages/MoriUI/Sources/MoriUI/Resources/` (MoriUI)
  - `Sources/MoriCLI/Resources/` (MoriCLI)

## Detailed Docs

- [Architecture](docs/architecture.md) — packages, data flow, UI structure, terminal rendering
- [Agent Hooks](docs/agent-hooks.md) — hook-based agent status tracking setup
- [Keymaps](docs/keymaps.md) — keyboard shortcuts reference
