# Plan: Ghostty-driven Mori chrome theme

## Problem
Mori already flips `NSAppearance` between `.darkAqua` and `.aqua` from `GhosttyThemeInfo.isDark`, but most app chrome still uses Ghostty’s raw terminal background directly. That makes dark themes feel acceptable while light themes collapse into a low-contrast white sheet: sidebar, content surround, settings, companion pane, and headers all sit on nearly the same surface with faint selection and divider states.

The goal is to keep Ghostty as the source of truth for theme choice — when the user picks a dark Ghostty theme in Settings, Mori should become dark; when they pick a light theme, Mori should become light — while making Mori’s non-terminal chrome read like a real macOS app instead of a terminal canvas stretched across the whole window.

## How we got here
I traced the current theme flow through the codebase:

- `Packages/MoriTerminal/Sources/MoriTerminal/GhosttyThemeInfo.swift` resolves Ghostty colors and computes `isDark` from background luminance.
- `Sources/Mori/App/AppDelegate.swift` writes the selected Ghostty theme to config, then calls `reloadGhosttyConfig()` after settings changes.
- `reloadGhosttyConfig()` already fans the new `themeInfo` out to the main window, sidebar, terminal area, companion pane, settings window, and tmux.
- `Sources/Mori/App/MainWindowController.swift`, `HostingControllers.swift`, `CompanionToolPaneController.swift`, `TerminalAreaViewController.swift`, `WorktreeCreationController.swift`, and `AgentDashboardPanel.swift` currently use Ghostty background colors directly for app chrome.
- `Packages/MoriUI/Sources/MoriUI/DesignTokens.swift`, `WorktreeRowView.swift`, and `WindowRowView.swift` use fixed highlight opacities that are too subtle against light backgrounds.
- `Sources/Mori/App/RootSplitViewController.swift` uses default separator hairlines, which disappear on very light surfaces.

That means the settings plumbing already exists; the missing piece is a better chrome palette and stronger light-mode hierarchy.

## Design decisions

### 1. Ghostty remains the single source of truth for Mori’s light/dark mode
**Decision:** Mori will continue deriving overall appearance mode from `GhosttyThemeInfo`. A dark Ghostty theme keeps Mori in dark appearance; a light Ghostty theme keeps Mori in light appearance.

**Alternatives considered:**
- Follow macOS system appearance for Mori chrome only. Rejected because it breaks the user expectation that changing the Ghostty theme in Mori Settings updates the whole app together.
- Add a separate manual Mori light/dark override now. Rejected for this pass because it adds product complexity before we fix the current visual model.

**Tradeoff:** Chrome and terminal remain coupled at the mode level, but not at the raw surface-color level. This plan does **not** change the existing `isDark` threshold logic; instead, Phase 4 will explicitly validate a few near-threshold Ghostty themes so we catch any surprising mode flips before shipping and spin threshold tuning into a follow-up if needed.

> **Tradeoff:** Chrome and terminal remain coupled at the mode level, but not at the raw surface-color level.

**Review (claude):** `isDark` is computed from background luminance with an undocumented threshold. Ghostty themes whose background sits near the boundary (warm sepia, muted teal) may produce unexpected appearance flips as users browse themes — dark-appearing themes classified as light, or vice versa. The plan accepts this coupling as a non-issue without acknowledging the threshold sensitivity or stating whether any clamping or hysteresis is planned.

**Resolved:** Kept the existing threshold behavior in scope for this plan, but documented that the validation phase must exercise near-threshold themes and treat threshold tuning as a follow-up if the current classification proves unstable.

### 2. Use a deterministic Ghostty → chrome derivation algorithm instead of ad-hoc tweaks
**Decision:** Introduce a shared `MoriChromePalette`-style value that is derived from `GhosttyThemeInfo` using one documented algorithm, not per-callsite color math. The derivation will:
- normalize Ghostty colors into shared sRGB helpers once,
- use the Ghostty background/effective background as the hue anchor,
- derive window/sidebar/panel/header surfaces by blending toward semantic macOS surfaces with fixed appearance-specific ratios,
- derive separators and selected/hover fills from Ghostty accent/selection colors but clamp them to minimum-contrast targets appropriate for light and dark mode.

That gives Mori one place to tune hierarchy while still feeling tied to the selected Ghostty theme.

**Alternatives considered:**
- Keep using `themeInfo.background` / `effectiveBackground` everywhere and only bump row highlight opacity. Rejected because it does not solve the missing surface hierarchy.
- Ignore Ghostty colors and use pure system colors only. Rejected because Mori should still feel connected to the selected Ghostty theme.
- Let each controller/view derive small adjustments locally. Rejected because it would recreate today’s drift in a different form.

**Tradeoff:** We introduce one more theming layer, but in return we get a stable, reviewable place to tune light-mode contrast without disturbing terminal rendering.

> Introduce a shared derived theme/palette type (name TBD: `MoriChromeTheme` or similar) that takes `GhosttyThemeInfo` and produces colors for app chrome surfaces: window background, sidebar background, secondary panels, headers, dividers, and selection fills.

**Review (claude):** The derivation algorithm is entirely unspecified — "takes `GhosttyThemeInfo` and produces colors" leaves open whether this is luminance-adjusted blending, fixed offsets in sRGB/HSL, or something else entirely. Without a concrete formula committed to here, every implementer will invent their own math, defeating the point of a single shared palette type. The core technical decision of this plan should not be deferred to Phase 1.

**Resolved:** Rewrote the decision to commit to one derivation strategy up front: shared color normalization helpers, fixed surface-blend ladders, and contrast-clamped selection/divider values.

### 3. Keep the palette type package-safe and inject it into `MoriUI`
**Decision:** Split ownership between a package-safe palette type and an app-side builder:
- `Packages/MoriUI` will own the palette/token value type plus any environment or initializer plumbing needed by row views and settings content.
- `Sources/Mori/App` will own the `GhosttyThemeInfo -> MoriChromePalette` builder and will pass the resulting palette into AppKit controllers and SwiftUI root views during startup and `reloadGhosttyConfig()`.

This keeps `MoriUI` free of upward dependencies on the app target and avoids forcing the package to import Ghostty-specific types directly.

**Alternatives considered:**
- Put both the palette type and the Ghostty-specific derivation logic in `Sources/Mori/App/`. Rejected because `MoriUI` cannot import the app target.
- Make `MoriUI` depend directly on `MoriTerminal`. Rejected for this change because the UI package only needs already-derived chrome tokens, not terminal-host responsibilities.
- Keep palette values entirely outside `MoriUI` and thread loose color parameters through every view. Rejected because it would make view APIs noisy and inconsistent.

**Tradeoff:** Theme propagation gains an extra injection step, but the package boundary stays clean and the shared palette remains usable from both AppKit hosts and SwiftUI views.

> `Packages/MoriUI/Sources/MoriUI/DesignTokens.swift`
>   - Introduce appearance-aware highlight/separator helpers or new tokens used by light-mode row styling.

**Review (claude):** `MoriUI` is a separate Swift package and cannot import `MoriChromeTheme` if it lives in `Sources/Mori/App/` — that would create an upward dependency from the package into the app target. The plan never resolves how the derived chrome colors reach `DesignTokens`, `WorktreeRowView`, and `WindowRowView`. Either `MoriChromeTheme` must move into a shared package, or the SwiftUI views must receive values via injection — neither path is chosen or designed here.

**Resolved:** Chose the split design explicitly: `MoriUI` owns the palette/token type and receives values by injection; the app target owns Ghostty-specific derivation and propagation.

### 4. Keep the raw Ghostty theme only where Mori is actually rendering terminal content
**Decision:** Raw `GhosttyThemeInfo` colors remain the source of truth only for terminal-facing surfaces: terminal canvas, transparent/glass handling, tmux synchronization, and any explicit terminal theme previews. All app-shell surfaces — main window, sidebar, settings window chrome, companion pane, worktree creation panel, dashboard panel, headers, row states, and split dividers — will use the derived chrome palette.

**Alternatives considered:**
- Apply the derived chrome palette to the terminal area too. Rejected because it would make the embedded terminal diverge from Ghostty and tmux.
- Continue deciding raw-vs-derived usage at each callsite during implementation. Rejected because it would make the palette API unstable while the migration is in flight.

**Tradeoff:** There will be a deliberate distinction between terminal canvas and app chrome, especially in light mode. That separation is the point.

> - [ ] Decide and document which surfaces continue using raw Ghostty colors versus derived chrome colors.

**Review (claude):** This is a design decision masquerading as an implementation task. Deferring the raw-vs-derived boundary to Phase 1 means the `MoriChromeTheme` API surface (which properties exist, what they're named) cannot be finalized until mid-implementation, risking churn across all Phase 2 callsites. The boundary should be defined in the plan before any code is written.

**Resolved:** Promoted the raw-vs-derived boundary into its own design decision and changed the Phase 1 task from "decide" to "codify/document" so implementation starts from a fixed surface map.

### 5. Make row selection, hover, and divider contrast appearance-aware
**Decision:** Strengthen light-mode hierarchy in sidebar rows, active states, and split dividers. Use appearance-aware values rather than one shared opacity for both schemes.

**Alternatives considered:**
- Keep one set of global opacity constants for all modes. Rejected because light mode needs visibly stronger separation than dark mode.
- Hard-code a bunch of one-off colors in row views. Rejected because it will drift and be hard to tune consistently.

**Tradeoff:** Some SwiftUI views will need palette-aware styling, but that is a contained change and fits macOS behavior.

## What changes where
- `Packages/MoriTerminal/Sources/MoriTerminal/GhosttyThemeInfo.swift`
  - Add or expose the shared color helpers the builder needs (for example normalized sRGB components, blending helpers, and luminance accessors) while keeping the raw Ghostty model authoritative.
- `Packages/MoriUI/Sources/MoriUI/` (new file, likely `MoriChromePalette.swift` plus environment/plumbing helpers)
  - Add the package-safe palette/token type consumed by row views and any SwiftUI settings chrome.
- `Packages/MoriUI/Sources/MoriUI/DesignTokens.swift`
  - Introduce appearance-aware highlight/separator helpers backed by the shared palette.
- `Packages/MoriUI/Sources/MoriUI/WorktreeRowView.swift`
  - Strengthen selected and hover presentation for light mode while preserving the current dark-mode feel.
- `Packages/MoriUI/Sources/MoriUI/WindowRowView.swift`
  - Strengthen active/hover row presentation and shortcut pill contrast for light mode.
- `Packages/MoriUI/Sources/MoriUI/TaskWorktreeRowView.swift`
  - Keep the alternate row implementation aligned with the same palette rules.
- `Sources/Mori/App/` (new file, likely `MoriChromeThemeBuilder.swift` or similar)
  - Add the Ghostty-specific builder that converts `GhosttyThemeInfo` into the shared `MoriChromePalette`, including the fixed derivation rules documented above.
- `Sources/Mori/App/MainWindowController.swift`
  - Stop setting the main window background directly from the raw terminal background; apply the derived chrome background while keeping `appearance` sourced from Ghostty dark/light.
- `Sources/Mori/App/HostingControllers.swift`
  - Inject the derived palette into sidebar/content hosting roots instead of relying on `themeInfo.effectiveBackground` alone.
- `Sources/Mori/App/CompanionToolPaneController.swift`
  - Apply derived body/header/divider colors so the companion pane has clear layering in light themes.
- `Sources/Mori/App/RootSplitViewController.swift`
  - Use stronger derived divider colors rather than a barely visible default separator on very light themes.
- `Sources/Mori/App/AppDelegate.swift`
  - Centralize creation and propagation of the derived chrome palette during startup and `reloadGhosttyConfig()` so theme changes made in Settings immediately restyle every affected surface, including the settings window.
- `Sources/Mori/App/WorktreeCreationController.swift`
  - Apply the derived chrome palette to the panel background/container while keeping light/dark mode synced to Ghostty.
- `Sources/Mori/App/AgentDashboardPanel.swift`
  - Apply the derived chrome background instead of the raw Ghostty background.

> `reloadGhosttyConfig()` already fans the new `themeInfo` out to the main window, sidebar, terminal area, companion pane, settings window, and tmux.

**Review (claude):** The settings window is explicitly listed as a current `reloadGhosttyConfig()` recipient in "How we got here," but it is absent from the "What changes where" section. If the settings window currently uses raw Ghostty background colors (the same pattern being fixed everywhere else), it should appear in the file list; if it doesn't need changes, that should be explicitly justified.

**Resolved:** Added the settings window explicitly to the `AppDelegate.swift` change list and to Phase 2 so it is part of the same palette propagation work as the main shell.

## Migration / implementation order
1. Define the package-safe palette type and the raw-vs-derived surface boundary first so the shared API is stable before any callsites move.
2. Implement the Ghostty → palette builder and wire `AppDelegate.reloadGhosttyConfig()` / startup propagation, including the settings window, before tuning individual views.
3. Update the AppKit shell surfaces next (`MainWindowController`, sidebar host, companion pane, split dividers, auxiliary panels). This establishes the new hierarchy and keeps refresh behavior centralized.
4. Update `MoriUI` row styling after the shell colors land; otherwise row contrast would be tuned against the wrong background assumptions.
5. Validate theme changes from Settings end to end, including near-threshold themes for `isDark`, to confirm Mori chrome updates live without regressing terminal or tmux behavior.

This sequence keeps the shared theme model stable before touching many visual callsites and lets the compiler surface all consumers that still depend on raw background colors.

## Tasks

### Phase 1: Define the shared palette contract
<!-- Do this first so package boundaries, surface ownership, and palette properties are fixed before any callers migrate. -->
- [x] Add a package-safe `MoriChromePalette`-style type in `MoriUI` for chrome surfaces, separators, and selection states.
- [x] Add any shared color math/helpers needed to derive those values cleanly from `GhosttyThemeInfo`.
- [x] Codify the raw-vs-derived surface boundary in palette docs/comments so later phases do not reopen the API.

### Phase 2: Build and propagate the palette from the app target
<!-- The app shell owns Ghostty config reloads today, so builder + propagation must land before AppKit or SwiftUI callers can rely on the palette. -->
- [x] Add the `GhosttyThemeInfo -> MoriChromePalette` builder with fixed blend/contrast rules.
- [x] Update `AppDelegate.reloadGhosttyConfig()` and startup wiring to propagate the derived palette alongside `GhosttyThemeInfo`.
- [x] Include the settings window in the same propagation path so Settings live-reloads with the rest of the app.
- [x] Keep `NSAppearance(named: themeInfo.isDark ? .darkAqua : .aqua)` behavior intact everywhere so Ghostty theme choice still controls dark vs. light mode.

### Phase 3: Apply the palette to AppKit shell surfaces
<!-- Do this after propagation exists so every controller can consume the same palette source. -->
- [x] Update `MainWindowController`, `HostingControllers`, and `CompanionToolPaneController` to use derived chrome backgrounds/headers/dividers.
- [x] Update `RootSplitViewController` divider styling to remain readable in light mode.
- [x] Update `WorktreeCreationController` and `AgentDashboardPanel` to use the same chrome palette.

### Phase 4: Strengthen `MoriUI` contrast for light themes
<!-- Do this after the shell colors settle so row tuning is based on the final surfaces rather than guessed backgrounds. -->
- [x] Add appearance-aware highlight helpers/tokens in `DesignTokens.swift`.
- [x] Update `WorktreeRowView` selected/hover styling for clearer light-mode hierarchy.
- [x] Update `WindowRowView` active/hover styling and shortcut pill contrast.
- [x] Update `TaskWorktreeRowView` to match the same rules.

### Phase 5: Validate Settings-driven theme sync end to end
<!-- Last, so validation happens on the final integrated behavior rather than on partial styling. -->
- [ ] Verify changing Ghostty theme in Settings live-updates Mori chrome without reopening windows.
- [ ] Verify switching between light and dark Ghostty themes flips Mori appearance mode correctly, including a few near-threshold themes.
- [ ] Verify terminal rendering, tmux theme sync, and transparent/glass modes still behave as before.
- [x] Run the relevant build/tests to catch regressions in shared packages and AppKit callsites.
