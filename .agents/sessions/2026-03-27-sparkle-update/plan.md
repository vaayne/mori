# Plan: Sparkle Auto-Update System

## Overview

Implement a Sparkle-based auto-update system for Mori, modeled after Ghostty's implementation. The system checks an appcast feed for new releases and shows an unobtrusive pill-shaped badge in the titlebar. Users can click it to view details and install updates in-app.

### Goals

- Automatic update checking via Sparkle 2 framework
- Titlebar update badge (top-right pill) with state-aware icons and progress
- In-app download, extract, install & relaunch flow
- CI generates and publishes `appcast.xml` to GitHub Pages (`gh-pages` branch)
- "Check for Updates…" menu item in the app menu
- Localization of all new strings (en + zh-Hans)

### Success Criteria

- [ ] Sparkle SPM dependency added and compiling
- [ ] EdDSA key generation documented; public key in Info.plist
- [ ] UpdateController, UpdateDriver, UpdateViewModel, UpdateState implemented
- [ ] UpdateBadge, UpdatePill, UpdatePopoverView rendering in titlebar
- [ ] "Check for Updates…" menu item functional
- [ ] CI workflow generates appcast.xml and publishes to gh-pages
- [ ] All new strings localized (en + zh-Hans)
- [ ] Build compiles with zero warnings under Swift 6 strict concurrency

### Out of Scope

- App Store distribution
- Delta updates (full download only for v1)
- Multiple update channels (tip vs stable) — single stable channel
- Custom download server — GitHub Releases URLs in appcast
- Auto-update toggle in Settings UI (use Sparkle defaults: check + notify)
- Signed feeds (`SURequireSignedFeed`) — EdDSA archive signing only for v1

## Technical Approach

### Architecture

The update system lives entirely in the `Mori` app target (not a separate package) since it's UI-facing and Sparkle is app-level infrastructure. The module follows Ghostty's pattern:

```
Sources/Mori/Update/
├── UpdateController.swift      # Wraps SPUUpdater, manages lifecycle
├── UpdateDriver.swift          # SPUUserDriver impl (callback → state)
├── UpdateDelegate.swift        # SPUUpdaterDelegate (feed URL, install hooks)
├── UpdateViewModel.swift       # ObservableObject state holder (Combine for sink)
├── UpdateState.swift           # State enum with associated data
├── UpdateBadge.swift           # SwiftUI badge (progress ring, animated icons)
├── UpdatePill.swift            # SwiftUI pill button (titlebar)
├── UpdatePopoverView.swift     # SwiftUI popover (detail + actions)
└── UpdateAccessoryView.swift   # NSHostingView wrapper for titlebar accessory
```

### Key Design Decisions

1. **`ObservableObject` (not `@Observable`) for UpdateViewModel**: Although Mori generally uses `@Observable`, the UpdateController's `installUpdate()` method needs Combine's `$state.sink` to create a force-install chain (listening for state changes and auto-confirming each step). `@Observable` doesn't support Combine publishers. UpdateViewModel uses `ObservableObject` with `@Published var state`. SwiftUI views use `@ObservedObject`. This matches Ghostty's approach exactly.

2. **`@MainActor` isolation**: UpdateController and UpdateViewModel are `@MainActor`. UpdateDriver bridges Sparkle callbacks (which arrive on main thread) to the view model.

3. **Titlebar accessory**: `NSTitlebarAccessoryViewController` with `layoutAttribute = .trailing` hosts an `NSHostingView` containing the `UpdatePill` SwiftUI view.

4. **Sparkle feed URL**: Provided via `SPUUpdaterDelegate.feedURLString(for:)` delegate method pointing to `https://vaayne.github.io/mori/appcast.xml`.

5. **Appcast hosting**: `gh-pages` branch of the mori repo. CI generates `appcast.xml` using Sparkle's `generate_appcast` tool and pushes to `gh-pages`.

6. **EdDSA signing**: Private key exported as CI secret (`SPARKLE_PRIVATE_KEY`). `generate_appcast` uses it to sign archives. Public key embedded in `Info.plist` as `SUPublicEDKey`.

### Components

- **UpdateController**: Owns `SPUUpdater` instance. Provides `startUpdater()`, `checkForUpdates()`, `installUpdate()`. Created in AppDelegate.
- **UpdateDriver**: Implements `SPUUserDriver` protocol. Translates Sparkle callbacks into `UpdateState` transitions on the view model. Falls back to `SPUStandardUserDriver` when no window is visible. Checks `hasUnobtrusiveTarget` by looking for visible `MainWindowController.window`.
- **UpdateDelegate**: `SPUUpdaterDelegate` conformance (separate file, as extension on UpdateDriver like Ghostty). Provides feed URL via `feedURLString(for:)`, handles `willInstallUpdateOnQuit` and `updaterWillRelaunchApplication`.
- **UpdateViewModel**: `ObservableObject` class with `@Published var state: UpdateState`. Uses Combine so UpdateController can `$state.sink` for the force-install chain. Computed properties for text, icon, colors. `@MainActor` isolated.
- **UpdateState**: Enum with cases: `.idle`, `.permissionRequest`, `.checking`, `.updateAvailable`, `.downloading`, `.extracting`, `.installing`, `.notFound`, `.error`. Each case carries associated data (progress, callbacks, appcast item).
- **UpdateBadge**: SwiftUI view showing progress ring or SF Symbol icon based on state.
- **UpdatePill**: Pill-shaped button wrapping badge + text. Shows popover on click. Auto-dismisses `.notFound` after 5s.
- **UpdatePopoverView**: Detail view with version info, progress bars, action buttons (Install, Skip, Later, Retry).
- **UpdateAccessoryView**: `NSTitlebarAccessoryViewController` subclass hosting the SwiftUI pill.

## Implementation Phases

### Phase 1: Sparkle Dependency & Infrastructure

1. Add Sparkle 2.x SPM dependency to `Package.swift`, pinned to `from: "2.7.0"` (files: `Package.swift`)
2. Create `Sources/Mori/Update/` directory structure
3. Add `SUPublicEDKey` (placeholder) and `SUFeedURL` to Info.plist generation in bundle script. Also add Sparkle framework + XPC services embedding step to `bundle.sh` (copy `Sparkle.framework` and its XPC services into `Contents/Frameworks/`, codesign them) (files: `scripts/bundle.sh`)
4. Document EdDSA key generation steps in `docs/auto-update.md` — clarify: public key is committed in bundle script, private key is exported with `-x` flag and stored as `SPARKLE_PRIVATE_KEY` GitHub secret

### Phase 2: Core Update Logic

1. Implement `UpdateState.swift` — state enum with all cases and associated data (files: `Sources/Mori/Update/UpdateState.swift`)
2. Implement `UpdateViewModel.swift` — `ObservableObject` with `@Published var state`, computed properties for text/icon/colors (files: `Sources/Mori/Update/UpdateViewModel.swift`)
3. Implement `UpdateDriver.swift` — `SPUUserDriver` protocol, translates Sparkle callbacks to UpdateState. `hasUnobtrusiveTarget` checks for visible MainWindowController window. Falls back to `SPUStandardUserDriver` (files: `Sources/Mori/Update/UpdateDriver.swift`)
4. Implement `UpdateDelegate.swift` — `SPUUpdaterDelegate` as extension on UpdateDriver. Provides feed URL, handles install-on-quit and relaunch (files: `Sources/Mori/Update/UpdateDelegate.swift`)
5. Implement `UpdateController.swift` — wraps SPUUpdater, start/check/install methods. `installUpdate()` uses Combine `$state.sink` for force-install chain (files: `Sources/Mori/Update/UpdateController.swift`)

### Phase 3: Update UI Components

1. Implement `UpdateBadge.swift` — progress ring + animated/static icons (files: `Sources/Mori/Update/UpdateBadge.swift`)
2. Implement `UpdatePill.swift` — pill button with badge + text, popover trigger (files: `Sources/Mori/Update/UpdatePill.swift`)
3. Implement `UpdatePopoverView.swift` — all state-specific detail views (files: `Sources/Mori/Update/UpdatePopoverView.swift`)
4. Implement `UpdateAccessoryView.swift` — NSTitlebarAccessoryViewController wrapper (files: `Sources/Mori/Update/UpdateAccessoryView.swift`)

### Phase 4: App Integration

1. Wire UpdateController into AppDelegate — create on launch, start updater (files: `Sources/Mori/App/AppDelegate.swift`)
2. Add titlebar accessory to MainWindowController (files: `Sources/Mori/App/MainWindowController.swift`)
3. Add "Check for Updates…" menu item to app menu (files: `Sources/Mori/App/AppDelegate.swift`)
4. Register update actions in command palette (files: `Sources/Mori/App/AppDelegate.swift`)

### Phase 5: CI & Appcast Pipeline

1. Create `scripts/generate-appcast.sh` — wrapper that: (a) downloads Sparkle release tarball to get `generate_appcast` binary (not from SPM artifacts, which aren't available in CI), (b) writes `SPARKLE_PRIVATE_KEY` secret to a temp file, (c) runs `generate_appcast` over the archive directory to produce `appcast.xml` with EdDSA signatures (files: `scripts/generate-appcast.sh`)
2. Add appcast generation + gh-pages publish step to release workflow. Step ordering: build → create archive (ditto) → run `generate-appcast.sh` to sign archive + generate appcast.xml → upload archive to GitHub Release → checkout gh-pages branch → copy appcast.xml → commit + push (files: `.github/workflows/release.yml`)
3. Create initial `gh-pages` branch structure with placeholder `index.html` and empty `appcast.xml`
4. Update `docs/auto-update.md` with the full signing + release flow, including how to regenerate keys if needed

### Phase 6: Localization & Polish

1. Add all new user-facing strings to en + zh-Hans String Catalogs (files: `Sources/Mori/Resources/en.lproj/`, `Sources/Mori/Resources/zh-Hans.lproj/`)
2. Use `.localized()` for all computed strings in update UI
3. Build and verify zero warnings under Swift 6 strict concurrency
4. Update CHANGELOG.md with the new feature entry

## Testing Strategy

- **Manual testing**: Temporarily decrease `CFBundleVersion`, build, run twice (Sparkle delays permission check), verify badge appears and popover works
- **Clear check timestamp**: `defaults delete com.mori.app SULastCheckTime` to force re-check
- **Console.app**: Monitor Sparkle logs for troubleshooting
- **CI validation**: Ensure `generate_appcast` runs without errors on release archives
- **UI testing**: Verify all UpdateState cases render correctly (badge icons, pill text, popover views)
- **Concurrency**: Verify no data races under Swift 6 strict concurrency (compiler enforced)

Note: Sparkle's update flow is inherently integration-level (requires network, signed archives, real appcast). Unit testing the state machine (UpdateState transitions, UpdateViewModel computed properties) is possible but the full flow requires manual verification.

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Sparkle SPM doesn't compile under Swift 6 strict concurrency | High | Sparkle 2.x is Obj-C based; Swift wrapper may need `@preconcurrency import`. Test early in Phase 1. |
| EdDSA key management in CI | Medium | Document key generation + export clearly. Store private key as GitHub secret. |
| `generate_appcast` tool availability in CI | Medium | Download Sparkle release tarball in CI to get the binary (SPM artifacts aren't available in CI runners). Script handles this. |
| Sparkle framework embedding in app bundle | Medium | `bundle.sh` must copy `Sparkle.framework` + XPC services into `Contents/Frameworks/` and codesign. Ghostty does this; adapt for Mori. |
| Titlebar accessory conflicts with existing toolbar | Low | Ghostty proves this works. Test layout with sidebar toggle button. |
| `@Observable` + Sparkle callback threading | Medium | Sparkle callbacks arrive on main thread. Verify with `@MainActor` assertions. |
| gh-pages branch publish permissions in CI | Low | Release workflow already has `contents: write`. May need separate deploy key for Pages. |

## Open Questions

All resolved — converted to assumptions:

- **Appcast hosting**: gh-pages branch at `https://vaayne.github.io/mori/appcast.xml`
- **Update behavior**: Check + notify (Sparkle defaults), no auto-install
- **UI design**: Same as Ghostty (pill + badge + popover)
- **EdDSA keys**: Will be generated; instructions documented

## Review Feedback

### Round 1

Reviewer raised 11 issues. All addressed:

1. **`@Observable` vs `ObservableObject`** (Critical) → Switched to `ObservableObject` + `@Published` for Combine `$state.sink` support in force-install chain. Matches Ghostty exactly.
2. **Separate `UpdateDelegate.swift`** (Medium) → Added as distinct file, SPUUpdaterDelegate as extension on UpdateDriver (Ghostty pattern).
3. **`generate_appcast` binary in CI** (High) → Script downloads Sparkle release tarball to get binary. Not relying on SPM artifacts.
4. **Sparkle framework embedding** (Critical) → Added to Phase 1 Task 3: `bundle.sh` copies Sparkle.framework + XPC services, codesigns them.
5. **CI step ordering** (Medium) → Phase 5 Task 2 now specifies: build → archive → sign+generate_appcast → upload → gh-pages push.
6. **`hasUnobtrusiveTarget`** (Low) → Phase 2 Task 3 specifies checking for visible MainWindowController window.
7. **EdDSA key clarity** (Low) → Phase 1 Task 4 clarifies public key committed, private key as secret.
8. **Sparkle version pin** (Low) → Pinned to `from: "2.7.0"` in Phase 1 Task 1.
9–11. Various minor items covered by above changes.

## Final Status

(Updated after implementation completes)
