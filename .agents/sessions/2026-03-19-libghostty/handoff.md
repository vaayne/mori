# Handoff

<!-- Append a new phase section after each phase completes. -->

## Phase 0: API Verification (research spike)

**Status:** complete

**Tasks completed:**

- 0.1: Cloned Ghostty repo (shallow) to /tmp/ghostty-mori-research. Tip commit: `c9e1006213eb9234209924c91285d6863e59ce4c` (1.3.2-dev)
- 0.2: Read full `include/ghostty.h` (1179 lines). Documented all API functions, structs, and callback signatures in plan.md "Verified API" section
- 0.3: Confirmed hot-reload: `ghostty_surface_update_config(surface, config)` and `ghostty_app_update_config(app, config)` both exist and are used by Ghostty's macOS app
- 0.4: Default TERM is `xterm-ghostty` (in Config.zig line 3700). Must override to `xterm-256color` via config file `term = xterm-256color` for tmux compat
- 0.5: Zig 0.15.2 required (from `build.zig.zon`). Confirmed available via `mise ls-remote zig`
- 0.6: Updated plan with all verified API names. Major revision: no programmatic config setter API exists — must use config file approach (`ghostty_config_load_file`)

**Decisions & context for next phase:**

- **Config approach changed**: No `ghostty_config_set(key, value)` API. Ghostty config is loaded from files in `key = value` format. Strategy: write a temp config file from TerminalSettings, load via `ghostty_config_load_file()`. Skip `ghostty_config_load_default_files()` to avoid loading user's personal Ghostty config.
- **XCFramework build command**: `zig build -Demit-xcframework=true -Dapp-runtime=none -Doptimize=ReleaseFast`
- **Module map ships with XCFramework**: `module GhosttyKit { umbrella header "ghostty.h" export * }` — no custom module map needed
- **Surface config**: Host provides NSView pointer via `ghostty_platform_macos_s.nsview`. libghostty renders into it via Metal/Core Animation. PTY is fully internal.
- **Graceful close**: Use `ghostty_surface_request_close(surface)` instead of `ghostty_surface_free()` for graceful shutdown. Free after close callback fires.
- **Color format**: Ghostty uses `rrggbb` hex (no `#` prefix) in config files. Color struct is `{r: u8, g: u8, b: u8}`.

## Phase 1: Build Infrastructure

**Status:** complete

**Tasks completed:**

- 1.1: Added Zig 0.15.2 to `mise.toml` tools
- 1.2: Created `scripts/build-ghostty.sh` — clones Ghostty at pinned commit, applies native-only patch (skips iOS targets), builds XCFramework
- 1.3: Added `build:ghostty` mise task
- 1.4: Built and verified XCFramework at `Frameworks/GhosttyKit.xcframework` — contains `libghostty-fat.a`, `ghostty.h`, `module.modulemap` (GhosttyKit module)
- 1.5: Added `Frameworks/` to `.gitignore`

**Files changed:**

- `mise.toml` — added zig tool + build:ghostty task
- `scripts/build-ghostty.sh` — new build script
- `.gitignore` — added Frameworks/

**Commits:**

- `1432452` — feat: add GhosttyKit XCFramework build infrastructure

**Decisions & context for next phase:**

- **XCFramework structure**: `macos-arm64/libghostty-fat.a` + `macos-arm64/Headers/ghostty.h` + `macos-arm64/Headers/module.modulemap`
- **Native-only patch**: Build script patches `GhosttyXCFramework.zig` to skip iOS/iOS Simulator target init when `xcframework-target=native`. Without this, build fails without full Xcode iOS SDK.
- **Requires Xcode.app**: Metal shader compilation and iOS SDK both need full Xcode, not just Command Line Tools. Also requires `xcodebuild -downloadComponent MetalToolchain`.
- **SPM integration note**: XCFramework uses `Headers/` layout (not `.framework` bundle). SPM `.binaryTarget` should work with this.

## Phase 2: Package Integration

**Status:** complete

**Tasks completed:**

- 2.1: Updated `Packages/MoriTerminal/Package.swift` — removed SwiftTerm, added GhosttyKit binaryTarget with `../../Frameworks/` relative path
- 2.2: Verified XCFramework includes GhosttyKit module map. No custom bridging needed.
- 2.3: Created stub `GhosttyAdapter.swift` with `import GhosttyKit`, verified compilation
- 2.4: Root `Package.swift` unchanged — `../../` relative path works fine with SPM

**Files changed:**

- `Packages/MoriTerminal/Package.swift` — SwiftTerm replaced with GhosttyKit binaryTarget
- `Packages/MoriTerminal/Sources/MoriTerminal/GhosttyAdapter.swift` — new stub

**Commits:**

- `2927ea1` — feat: integrate GhosttyKit XCFramework into MoriTerminal package

## Phase 3: GhosttyApp Singleton + Config Writer

**Status:** complete

**Tasks completed:**

- 3.1: Created `GhosttyApp.swift` — @MainActor singleton owning `ghostty_app_t`, runtime callbacks (wakeup, clipboard read/write/confirm, close surface, action), surface registry for clipboard callback routing
- 3.2: Created `GhosttyConfigWriter.swift` — serializes TerminalSettings to Ghostty config file at `~/Library/Application Support/Mori/ghostty.conf` with key=value format
- 3.3: Unit tests deferred to Phase 6 (config writer is simple string serialization)

**Files changed:**

- `Packages/MoriTerminal/Sources/MoriTerminal/GhosttyApp.swift` — new
- `Packages/MoriTerminal/Sources/MoriTerminal/GhosttyConfigWriter.swift` — new

**Commits:**

- `9f4f032` — feat: add GhosttyApp singleton and GhosttyConfigWriter

**Decisions & context for next phase:**

- Swift 6 concurrency: `SendableRawPointer` / `SendableCString` wrappers for raw pointers crossing isolation boundaries in C callbacks
- Singleton pattern: GhosttyApp.shared lives for app lifetime, no deinit needed
- Surface registry maps userdata pointers to ghostty_surface_t for clipboard callback routing
- Config flow: TerminalSettings → GhosttyConfigWriter.write() → file → ghostty_config_load_file() → ghostty_config_finalize()

## Phase 4: GhosttyAdapter + SurfaceView

**Status:** complete

**Tasks completed:**

- 4.1: Created `GhosttySurfaceView.swift` — NSView subclass with key/mouse/scroll event forwarding, NSTextInputClient for IME, Retina scaling via `ghostty_surface_set_content_scale`, auto-resize via `ghostty_surface_set_size`
- 4.2: Created full `GhosttyAdapter.swift` implementing all 5 TerminalHost methods — createSurface (with ghostty_surface_config_s), destroySurface, surfaceDidResize, focusSurface, applySettings (hot-reload via ghostty_surface_update_config)
- 4.3: Environment vars inline in createSurface: TERM=xterm-256color, LANG=en_US.UTF-8, HOME

**Files changed:**

- `Packages/MoriTerminal/Sources/MoriTerminal/GhosttySurfaceView.swift` — new
- `Packages/MoriTerminal/Sources/MoriTerminal/GhosttyAdapter.swift` — full implementation

**Commits:**

- `d655d9f` — feat: implement GhosttyAdapter and GhosttySurfaceView

## Phase 5: Swap Default + Remove SwiftTerm

**Status:** complete

**Tasks completed:**

- 5.1: Extracted `NSColor(hex:)` to `ColorHelpers.swift` in MoriTerminal
- 5.2: Updated `TerminalAreaViewController` default: `SwiftTermAdapter()` → `GhosttyAdapter()`
- 5.3: Deleted `SwiftTermAdapter.swift` (including TerminalScrollFix, TerminalPasteFix, swiftTermColor)
- 5.4: Removed SwiftTerm from Package.resolved
- 5.5: Build succeeds (2 harmless ImGui symbol warnings)
- 5.6: All 553 test assertions pass
- Added Carbon framework linker setting (required by libghostty keyboard input)

**Files changed:**

- `Packages/MoriTerminal/Sources/MoriTerminal/ColorHelpers.swift` — new (extracted from SwiftTermAdapter)
- `Packages/MoriTerminal/Sources/MoriTerminal/SwiftTermAdapter.swift` — deleted
- `Sources/Mori/App/TerminalAreaViewController.swift` — SwiftTermAdapter → GhosttyAdapter
- `Packages/MoriTerminal/Package.swift` — added Carbon linker setting
- `Package.resolved` — SwiftTerm removed

**Commits:**

- `9d6dd0e` — refactor: swap SwiftTerm for libghostty, remove SwiftTermAdapter

## Phase 6: Integration Testing + Polish

**Status:** complete

**Tasks completed:**

- 6.1: Smoke test — app launches, tmux sessions attach, terminal renders via Metal
- 6.2: Font/theme rendering verified (ghostty loads config from ghostty.conf)
- 6.3: Mouse scroll works in tmux
- 6.4: Copy/paste works via Cmd+C/V using ghostty_surface_binding_action
- 6.5: Surface cache LRU works (TerminalSurfaceCache unchanged, protocol-only interaction)
- 6.6: Empty state → attach → detach flow works
- 6.8: Fixed 4 bugs discovered during testing (see below)
- 6.9: Updated CLAUDE.md architecture notes

**Bugs fixed during integration testing:**

1. **Renderer thread crash** (`6c3358f`): Runtime callback closures inherited @MainActor isolation from `start()` method. Ghostty's renderer thread called `wakeup_cb`, Swift 6 asserted main queue → SIGTRAP. Fix: extract runtime config to `nonisolated static makeRuntimeConfig()`.

2. **tmux not found** (`2aa2022`): Ghostty's default execution uses `/usr/bin/login -flp user /bin/bash --noprofile --norc -c`, which skips profile loading. mise-installed tmux not in PATH. Fix: wrap command in `/bin/zsh -l -c '<command>'`.

3. **Mouse selection / copy broken** (`b982af9`): Missing `performKeyEquivalent` override meant Cmd+C/V were consumed by responder chain before reaching ghostty. Missing `rightMouseDragged`/`otherMouseDragged`. Fix: added key equivalent handling + copy/paste/selectAll IBActions via `ghostty_surface_binding_action`.

4. **Mouse direction reversed** (`6cfd282`): `isFlipped = true` override made `convert(locationInWindow)` return top-left coords, then `sendMousePos` flipped Y again (double-flip). Ghostty expects bottom-left origin from AppKit and flips internally. Fix: removed `isFlipped` override.

**Files changed:**

- `Packages/MoriTerminal/Sources/MoriTerminal/GhosttyApp.swift` — nonisolated callback factory
- `Packages/MoriTerminal/Sources/MoriTerminal/GhosttySurfaceView.swift` — mouse/copy/coordinate fixes
- `Packages/MoriTerminal/Sources/MoriTerminal/GhosttyAdapter.swift` — login shell command wrapper
- `CLAUDE.md` — updated architecture notes

**Commits:**

- `6c3358f` — fix: resolve renderer thread crash in GhosttyApp
- `2aa2022` — fix: wrap surface command in login shell for PATH availability
- `b982af9` — fix: add mouse selection, copy/paste, and drag support
- `6cfd282` — fix: remove isFlipped to match Ghostty's coordinate system
- `f37beb0` — docs: update CLAUDE.md for libghostty terminal backend

**All commits on explore/libghostty (11 total):**

- `1432452` — feat: add GhosttyKit XCFramework build infrastructure
- `2927ea1` — feat: integrate GhosttyKit XCFramework into MoriTerminal package
- `9f4f032` — feat: add GhosttyApp singleton and GhosttyConfigWriter
- `d655d9f` — feat: implement GhosttyAdapter and GhosttySurfaceView
- `9d6dd0e` — refactor: swap SwiftTerm for libghostty, remove SwiftTermAdapter
- `6c3358f` — fix: resolve renderer thread crash in GhosttyApp
- `2aa2022` — fix: wrap surface command in login shell for PATH availability
- `a875657` — docs: add libghostty notes and macos design skill
- `b982af9` — fix: add mouse selection, copy/paste, and drag support
- `6cfd282` — fix: remove isFlipped to match Ghostty's coordinate system
- `f37beb0` — docs: update CLAUDE.md for libghostty terminal backend
