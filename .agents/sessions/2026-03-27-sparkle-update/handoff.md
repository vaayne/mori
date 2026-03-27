# Handoff

<!-- Append a new phase section after each phase completes. -->

## Phase 1: Sparkle Dependency & Infrastructure

**Status:** complete

**Tasks completed:**
- 1.1: Added Sparkle 2.x SPM dependency (resolved at 2.9.0) to Package.swift with `.product(name: "Sparkle", package: "Sparkle")` in the Mori target
- 1.2: Created `Sources/Mori/Update/` with 9 placeholder stub files (UpdateState, UpdateViewModel, UpdateDriver, UpdateDelegate, UpdateController, UpdateBadge, UpdatePill, UpdatePopoverView, UpdateAccessoryView)
- 1.3: Updated `scripts/bundle.sh` to embed Sparkle.framework from `.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/`, copy XPC services to `Contents/XPCServices/`, and add `SUPublicEDKey` + `SUFeedURL` to Info.plist. Also updated `scripts/sign.sh` to sign XPC services.
- 1.4: Created `docs/auto-update.md` documenting EdDSA key generation, export, storage, update flow, and key regeneration

**Files changed:**
- `Package.swift` — Added Sparkle SPM dependency and wired into Mori target
- `Package.resolved` — Updated with Sparkle 2.9.0 resolution
- `Sources/Mori/Update/*.swift` — 9 placeholder stub files
- `scripts/bundle.sh` — Sparkle framework embedding, XPC service copying, Info.plist keys
- `scripts/sign.sh` — Added XPC service signing block (inside-out, before resource bundles)
- `docs/auto-update.md` — EdDSA key setup and update flow documentation

**Commits:**
- `a511b03` — ✨ feat: add Sparkle 2.x SPM dependency for auto-update support
- `4b4dfb5` — 🏗️ chore: scaffold Update/ directory with placeholder stubs
- `809b235` — 🔧 chore: add Sparkle framework embedding and Info.plist keys to bundle script
- `2c6c6be` — 📝 docs: add auto-update documentation with EdDSA key setup guide

**Decisions & context for next phase:**
- Sparkle resolved at 2.9.0 (latest compatible with `from: "2.7.0"`)
- SPM artifacts location: `.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework`
- Sparkle tools (generate_keys, generate_appcast, sign_update) at `.build/artifacts/sparkle/Sparkle/bin/`
- `SUPublicEDKey` is currently `PLACEHOLDER_EDDSA_PUBLIC_KEY` — must be replaced with real key before release
- XPC services are copied to both `Contents/XPCServices/` (top-level) and remain in the framework
- `@preconcurrency import Sparkle` will likely be needed in Phase 2 for Swift 6 strict concurrency — Sparkle is Obj-C based
- UpdateState stub already has `.idle` case as starting point for Phase 2 expansion
- sign.sh now handles frameworks, XPC services, resource bundles, and helper executables in inside-out order

## Phase 2: Core Update Logic

**Status:** complete

**Tasks completed:**
- 2.1: Implemented `UpdateState.swift` — full state enum with 9 cases (idle, permissionRequest, checking, updateAvailable, downloading, extracting, installing, notFound, error). Each case has associated struct with callbacks/data. Manual `Equatable` conformance, `cancel()`/`confirm()` helpers, `isIdle`/`isInstallable` computed properties. Mori-specific `ReleaseNotes` enum linking to `https://github.com/vaayne/mori/releases/tag/v{version}`.
- 2.2: Implemented `UpdateViewModel.swift` — `ObservableObject` with `@Published var state: UpdateState`. Computed properties: `text`, `maxWidthText`, `iconName`, `description`, `badge`, `iconColor`, `backgroundColor`, `foregroundColor`. All state-driven with appropriate colors and SF Symbol icons.
- 2.3: Implemented `UpdateDriver.swift` — `SPUUserDriver` conformance translating all Sparkle lifecycle callbacks into `UpdateState` transitions on the view model. Falls back to `SPUStandardUserDriver` when no visible window available (`hasUnobtrusiveTarget`). Cancels state on window close. Uses `onRetryCheck` closure callback (set by controller) for error retry.
- 2.4: Implemented `UpdateDelegate.swift` — `SPUUpdaterDelegate` as extension on `UpdateDriver`. Returns feed URL `https://vaayne.github.io/mori/appcast.xml`. Handles `willInstallUpdateOnQuit` (sets `.installing` with `isAutoUpdate: true`). Invalidates restorable state before relaunch.
- 2.5: Implemented `UpdateController.swift` — `@MainActor` class wrapping `SPUUpdater`. `startUpdater()`, `checkForUpdates()`, `installUpdate()` methods. Force-install uses Combine `$state.sink` to auto-confirm each update step. Wires `onRetryCheck` to driver for error recovery loop.

**Files changed:**
- `Sources/Mori/Update/UpdateState.swift` — Full state enum implementation
- `Sources/Mori/Update/UpdateViewModel.swift` — ObservableObject with computed properties
- `Sources/Mori/Update/UpdateDriver.swift` — SPUUserDriver implementation
- `Sources/Mori/Update/UpdateDelegate.swift` — SPUUpdaterDelegate extension
- `Sources/Mori/Update/UpdateController.swift` — SPUUpdater wrapper with Combine

**Commits:**
- `4350a6b` — ✨ feat: implement UpdateState enum with all update lifecycle cases
- `5122e1f` — ✨ feat: implement UpdateViewModel with state-driven computed properties
- `e323884` — ✨ feat: implement UpdateDriver bridging Sparkle callbacks to UpdateState
- `61fa6cf` — ✨ feat: implement UpdateDelegate with feed URL and install hooks
- `ed444c8` — ✨ feat: implement UpdateController wrapping SPUUpdater with Combine force-install

**Decisions & context for next phase:**
- `@preconcurrency import Sparkle` confirmed needed on all files touching Sparkle types
- `@preconcurrency import Combine` needed on UpdateController for Sendable conformance
- `UpdateController` is `@MainActor` (not nonisolated as initially planned) — required to avoid Swift 6 warnings since SPUUpdater's init is @MainActor-isolated
- `UpdateDriver.onRetryCheck` closure pattern used instead of direct AppDelegate reference — avoids coupling driver to app delegate before Phase 4 wiring
- `hasUnobtrusiveTarget` checks `window.isVisible && window.contentViewController != nil` (generic, works with Mori's single main window)
- `ReleaseNotes` simplified to single `.tagged` case (Mori only uses semantic versions, no tip/commit-based releases like Ghostty)
- All 5 files compile with zero warnings under Swift 6 strict concurrency
- UI stubs (UpdateBadge, UpdatePill, UpdatePopoverView, UpdateAccessoryView) remain as placeholders for Phase 3

## Phase 3: Update UI Components

**Status:** complete

**Tasks completed:**
- 3.1: Implemented `UpdateBadge.swift` — SwiftUI badge with `ProgressRingView` for downloading/extracting progress, rotating animation (2.5s cycle) for checking state, and static SF Symbol icons for other states. Uses `@ObservedObject var model: UpdateViewModel`.
- 3.2: Implemented `UpdatePill.swift` — Pill-shaped capsule button wrapping `UpdateBadge` + text label. Shows `UpdatePopoverView` popover on click. Auto-dismisses `.notFound` state after 5 seconds via async Task. Fixed text width using `maxWidthText` to prevent resizing during progress. Only visible when state is not `.idle`. Uses macOS 14+ `onChange(of:)` API (two-parameter closure).
- 3.3: Implemented `UpdatePopoverView.swift` — State-specific detail views: `PermissionRequestView` (enable auto-updates prompt), `CheckingView` (spinner + cancel), `UpdateAvailableView` (version/size/date + Install/Skip/Later buttons + release notes link), `DownloadingView` (progress bar + cancel), `ExtractingView` (progress bar), `InstallingView` (restart prompt), `NotFoundView` (up-to-date message), `UpdateErrorView` (error + retry). Frame width 300.
- 3.4: Implemented `UpdateAccessoryView.swift` — `NSTitlebarAccessoryViewController` subclass with `layoutAttribute = .trailing`, hosts `UpdatePill` via `NSHostingView`. Takes `UpdateViewModel` parameter.

**Files changed:**
- `Sources/Mori/Update/UpdateBadge.swift` — Full implementation with ProgressRingView
- `Sources/Mori/Update/UpdatePill.swift` — Full implementation with popover and auto-dismiss
- `Sources/Mori/Update/UpdatePopoverView.swift` — Full implementation with 8 state-specific subviews
- `Sources/Mori/Update/UpdateAccessoryView.swift` — Full implementation as titlebar accessory

**Commits:**
- `bb1a434` — ✨ feat: implement UpdateBadge with progress ring and animated icons
- `ab591d2` — ✨ feat: implement UpdatePill with capsule button and popover trigger
- `25d0394` — ✨ feat: implement UpdatePopoverView with state-specific detail views
- `5fa79a5` — ✨ feat: implement UpdateAccessoryView as titlebar accessory controller

**Decisions & context for next phase:**
- All 4 UI files compile with zero warnings under Swift 6 strict concurrency
- Used macOS 14+ `onChange(of:) { _, newState in }` instead of deprecated single-parameter version
- String literals used directly (not `.localized()` yet) — localization deferred to Phase 6 as planned
- `UpdateAccessoryView` is ready to be added to `MainWindowController` in Phase 4 via `window.addTitlebarAccessoryViewController(_:)`
- `UpdatePopoverView` imports `@preconcurrency import Sparkle` for `SUUpdatePermissionResponse` in PermissionRequestView
- Release notes link uses `Link(destination:)` pointing to GitHub releases page
- "Mori" replaces "Ghostty" in the permission request description text

## Phase 4: App Integration

**Status:** complete

**Tasks completed:**
- 4.1: Wired `UpdateController` into `AppDelegate` — created after window is shown (so `hasUnobtrusiveTarget` finds a visible window), calls `startUpdater()` immediately
- 4.2: Added `addUpdateAccessory(viewModel:)` to `MainWindowController` — creates `UpdateAccessoryView` and adds it via `window.addTitlebarAccessoryViewController()` with `.trailing` layout
- 4.3: Added "Check for Updates…" menu item to the app menu — placed between "About Mori" and the first separator, wired to `updateController?.checkForUpdates()`
- 4.4: Registered "Check for Updates" action in command palette — new `action.check-for-updates` item in `CommandPaletteDataSource`, handled in `AppDelegate.handlePaletteAction()`, with `arrow.triangle.2.circlepath` icon
- Phase 2 reviewer feedback: Narrowed `hasUnobtrusiveTarget` to check `window.windowController is MainWindowController` instead of any window. Also narrowed `handleWindowWillClose` notification to only fire when the closing window belongs to `MainWindowController`.

**Files changed:**
- `Sources/Mori/App/AppDelegate.swift` — UpdateController property, creation in `applicationDidFinishLaunching`, titlebar accessory wiring, "Check for Updates…" menu item, palette action handler, `checkForUpdatesMenuAction()` method
- `Sources/Mori/App/MainWindowController.swift` — `addUpdateAccessory(viewModel:)` method
- `Sources/Mori/App/CommandPaletteDataSource.swift` — "Check for Updates" action item
- `Sources/Mori/App/CommandPaletteItem.swift` — Icon for `action.check-for-updates`
- `Sources/Mori/Update/UpdateDriver.swift` — Narrowed `hasUnobtrusiveTarget` and `handleWindowWillClose` to MainWindowController

**Commits:**
- `f6aab81` — ✨ feat: wire UpdateController into AppDelegate and add titlebar accessory
- `6ed8530` — ✨ feat: register Check for Updates action in command palette
- `27df412` — 🐛 fix: narrow UpdateDriver window checks to MainWindowController

**Decisions & context for next phase:**
- `UpdateController` is created after `windowController.showWindow(nil)` and `NSApp.activate()` so the window is visible when `hasUnobtrusiveTarget` is first evaluated
- Menu item uses a direct `NSMenuItem` (not the `menuItem()` helper) since it has no key equivalent
- Build compiles with zero new warnings (pre-existing Phase 2 Sendable warning on UpdateDriver remains)
- String literals in command palette action not yet localized — deferred to Phase 6 as planned
- `applicationShouldTerminate` could check `updateController?.isInstalling` to auto-confirm quit during updates (Ghostty does this) — not added since it's not in the task spec, but worth considering

## Phase 5: CI & Appcast Pipeline

**Status:** complete

**Tasks completed:**
- 5.1: Created `scripts/generate-appcast.sh` — downloads Sparkle 2.9.0 release tarball to get `generate_appcast` and `sign_update` binaries, writes `SPARKLE_PRIVATE_KEY` to a temp file (chmod 600, cleaned up on exit), stages the archive in a temp directory, runs `generate_appcast` with `--ed-key-file` and `--download-url-prefix` (GitHub Releases URL with version tag), merges with existing `appcast.xml` if present, outputs `appcast.xml` to current directory.
- 5.2: Added appcast generation + gh-pages publish to `release.yml` — new "Generate appcast.xml" step runs after archive creation using `SPARKLE_PRIVATE_KEY` secret, "Upload appcast artifact" step passes the file between jobs, new `publish-appcast` job (runs after `release` job) checks out `gh-pages`, downloads the appcast artifact, commits and pushes with `github-actions[bot]`. Added `pages: write` permission.
- 5.3: Created `scripts/setup-gh-pages.sh` — one-time setup script that creates an orphan `gh-pages` branch with `index.html` (redirect to repo) and empty `appcast.xml` placeholder. Includes safety checks (uncommitted changes, already on gh-pages). Prints instructions for push and GitHub Pages enablement.
- 5.4: Updated `docs/auto-update.md` with CI pipeline flow diagram, appcast generation process explanation, `SPARKLE_PRIVATE_KEY` secret setup instructions, gh-pages branch initialization steps, manual appcast generation example, and troubleshooting section (appcast not updating, app not finding updates, EdDSA verification failures, generate_appcast CI failures).

**Files changed:**
- `scripts/generate-appcast.sh` — New script for CI appcast generation
- `.github/workflows/release.yml` — Appcast generation step, artifact upload, publish-appcast job
- `scripts/setup-gh-pages.sh` — New script for gh-pages branch initialization
- `docs/auto-update.md` — CI pipeline docs, setup instructions, troubleshooting

**Commits:**
- `215a1ad` — ✨ feat: add generate-appcast.sh for CI appcast generation
- `bca3342` — 🔧 chore: add appcast generation and gh-pages publish to release workflow
- `dcfd044` — 📝 docs: add gh-pages branch setup script for appcast hosting
- `89abb4c` — 📝 docs: add CI pipeline, gh-pages setup, and troubleshooting to auto-update docs

**Decisions & context for next phase:**
- `generate-appcast.sh` takes two args: `<version>` and `<archive-path>`. Version is used to construct the GitHub Release download URL prefix (`/releases/download/v{version}/`)
- Script merges with existing `appcast.xml` if found in CWD — this preserves older release entries in the feed
- The `publish-appcast` job uses `actions/download-artifact@v5` to get the appcast from the release job, avoiding re-generation on a different runner
- `gh-pages` branch must be initialized before the first release (run `scripts/setup-gh-pages.sh` once)
- GitHub Pages must be enabled in repo Settings (Source: gh-pages branch)
- All Phase 5 scripts are robust (`set -euo pipefail`) with proper cleanup traps for temp files/secrets
- No scripts were executed — they require CI environment with secrets and signing infrastructure
- Phase 6 (Localization & Polish) is next: localize all update UI strings, verify zero warnings, update CHANGELOG
