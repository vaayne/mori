# AGENTS.md

Guidance for AI coding agents working in this repository.

## Build & Test

```bash
mise run build           # Debug build
mise run build:release   # Release build
mise run dev             # Build + run the app
mise run test            # All tests (parallel across packages)
mise run test:core       # MoriCore tests only
mise run test:git        # MoriGit tests only
mise run test:persistence # MoriPersistence tests only
mise run test:tmux       # MoriTmux tests only
mise run test:ipc        # MoriIPC tests only
mise run test:ui         # MoriUI tests only
mise run clean           # Remove .build and .derived-data
```

Tests are executable targets (not XCTest), run via `swift run <TestTarget>` from each package directory.

## Pre-Push Verification

Before pushing changes, replicate the CI pipeline locally to catch failures early:

```bash
# 1. Run tests (same as CI)
mise run test

# 2. Build both products in release mode (catches strict concurrency errors)
swift build -c release --product Mori
swift build --build-path .build-cli -c release --product mori

# 3. Bundle and verify the app launches (catches rpath, signing, resource issues)
CI=1 bash scripts/bundle.sh
./Mori.app/Contents/MacOS/Mori &  # should not crash; kill after verifying
```

Debug builds may miss errors that only appear in release mode (e.g., Swift 6 sendability).
Always build release before tagging.

## Key Conventions

- **Swift 6 strict concurrency**: UI code is `@MainActor`, tmux/git use actors
- **macOS 14+ (Sonoma)**: Required for `@Observable` macro
- **AppKit-first**: SwiftUI only for sidebar leaf views, AppKit for terminal and window management
- **SwiftUI views are pure**: Data + callbacks as parameters, no direct AppState dependency
- **No XCTest**: Tests are executable targets with custom `assertEqual`/`assertTrue` helpers

## Theme / Appearance

All windows and panels **must** sync their appearance with the Ghostty terminal theme.
The theme is resolved via `GhosttyThemeInfo` (from `MoriTerminal`) and fanned out by a single
registry, `ThemeDistributor` (`Sources/Mori/App/ThemeDistributor.swift`).
`AppDelegate.propagateGhosttyTheme(adapter:)` just broadcasts the current theme — on config
reload (`reloadGhosttyConfig()`) and on system dark/light changes (`handleSystemAppearanceChange()`).
Split themes (`theme = light:…,dark:…`) resolve per appearance: Mori pushes the color scheme
to libghostty via `GhosttyAdapter.setColorScheme(_:)` and re-extracts chrome colors for the
matching variant (libghostty exposes no API to query the non-active variant from a config).

When adding a new window, panel, or themed view:
1. Conform the owning object to `ThemedSurface`. Opaque chrome windows just expose the
   window through `themedWindow` and inherit the default `applyTheme` (appearance +
   `themeInfo.background`). Bespoke chrome (tints, glass, translucency, per-key-window state)
   overrides `applyTheme` and returns `nil` from `themedWindow`.
2. Call `themeDistributor.register(_:)` once when the object is created. Registration applies
   the current theme immediately, so lazily-created panels open already themed; later theme
   changes reach them automatically. Raw windows without a controller object (main window,
   settings window) use a retained `WindowThemedSurface` closure bridge.

tmux is deliberately **not** a `ThemedSurface` — it re-applies only on real theme changes
(in `propagateGhosttyTheme`), never on the window key/full-screen repaints that also broadcast.

SwiftUI views inside `NSHostingView` automatically inherit the window's `NSAppearance`,
so semantic colors like `Color.primary` and `Color(nsColor: .controlBackgroundColor)`
adapt correctly — no manual dark/light branching needed in SwiftUI. The semantic slots
on `MoriTokens.Color` (error/success/warning/attention/info/active) go further: they are
derived from the theme's ANSI palette by `MoriThemeBridge` (a registered `ThemedSurface`)
via `SemanticPalette.derive`, and fall back to system colors for palette-less themes.

Existing examples: `HeaderBarView` (the center column's 38pt chrome header),
`SidebarHostingController`, `TerminalAreaViewController`, `CompanionToolPaneController`
(whose `applyTheme` also paints its Files/Git tab bar), `CommandPaletteController`,
`AgentDashboardPanel`, `WorktreeCreationController`, and the `WindowThemedSurface` bridges
for the main and settings windows.

## Release

See [release skill](.agents/skills/release/SKILL.md) for the full release workflow.

### TestFlight Version Rule

For MoriRemote TestFlight uploads, keep the iOS marketing version fixed at `0.3.5` unless the user explicitly asks to change it. When publishing a new TestFlight build, reuse version `0.3.5` and only increment the build number.

## Docs to Keep in Sync

- **`CHANGELOG.md`** — entry under `[Unreleased]` for every user-visible change
- **`CHANGELOG.zh-Hans.md`** — always update Chinese changelog when updating English version
- **`AGENTS.md`** — update if build commands or conventions change
- **`README.md`** — update if features, install steps, or usage change
- **`README.zh-Hans.md`** — always update Chinese README when updating English version

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
