# Plan: Replace SwiftTerm with libghostty

## Overview

Replace the SwiftTerm terminal rendering backend with libghostty (Ghostty's embeddable terminal library). This is a full replacement — SwiftTerm is removed entirely. libghostty provides GPU-accelerated rendering, native mouse/scroll/paste handling, and internal PTY management, eliminating the workarounds currently needed for SwiftTerm.

### Goals

- Full feature parity with current SwiftTermAdapter (colors, fonts, cursor, mouse, scroll, paste, tmux compat)
- GPU-accelerated terminal rendering via libghostty
- Eliminate SwiftTerm workarounds (TerminalScrollFix, TerminalPasteFix)
- Clean integration through existing TerminalHost protocol (no protocol changes)

### Success Criteria

- [ ] `mise run build` succeeds with zero warnings
- [ ] Terminal surfaces render correctly (colors, cursor, mouse, scroll, paste)
- [ ] tmux attach/detach works as before
- [ ] TerminalSurfaceCache works unchanged
- [ ] TerminalSettings (font, theme, cursor style) apply correctly via applySettings
- [ ] No SwiftTerm references remain in codebase
- [ ] XCFramework build is reproducible via mise task

### Out of Scope

- Changing the TerminalHost protocol
- Modifying TerminalSurfaceCache, WorkspaceManager, or other consumers
- Adding new terminal features beyond current parity
- CI/CD pipeline for automatic XCFramework builds
- Removing NativeTerminalAdapter (kept as emergency fallback)

### Assumptions

- Ghostty version: Pin to commit `c9e1006213eb9234209924c91285d6863e59ce4c` (1.3.2-dev tip)
- Zig version: `0.15.2` (from Ghostty's `build.zig.zon`)
- XCFramework stored in-repo at `Frameworks/GhosttyKit.xcframework`, .gitignored (too large for git)
- Config mapping via temporary config file loaded with `ghostty_config_load_file()` (no programmatic setter API exists)
- `NSColor(hex:)` extension moves to `Packages/MoriTerminal/Sources/MoriTerminal/ColorHelpers.swift` (used by 3 app-target files: `AppDelegate.swift`, `TerminalAreaViewController.swift`, `MainWindowController.swift`)

### Rollback Strategy

SwiftTermAdapter deletion is a single commit in Phase 5. If libghostty has issues post-merge, `git revert` that commit and the default-swap commit to restore SwiftTerm. The branch history preserves the full SwiftTerm code.

## Technical Approach

### Architecture

libghostty follows an app->surface model:
1. **ghostty_app_t** — singleton application context, owns config and event loop integration
2. **ghostty_surface_t** — individual terminal surface, bound to an NSView

The host provides:
- An NSView for rendering (libghostty draws into it via Metal/Core Animation)
- Runtime callbacks for clipboard, wakeup, and action handling
- Event forwarding (keyboard, mouse) via C API functions

### Key Design Decisions

1. **GhosttyApp singleton** — A `@MainActor` class that owns `ghostty_app_t`, runtime callbacks, and a tick timer. Created once at app launch, shared by all surfaces.

2. **GhosttyAdapter: TerminalHost** — Holds a reference to GhosttyApp. `createSurface()` creates an NSView, passes its raw pointer to `ghostty_surface_new()`, and stores the mapping.

3. **Configuration bridging** — `TerminalSettings` -> ghostty config via a temporary config file written to `~/Library/Application Support/Mori/ghostty.conf`. File uses Ghostty's `key = value` format. Loaded via `ghostty_config_load_file()`, skipping default file loading.

4. **No user-facing config file** — The temp config file is managed internally by Mori. Users configure via TerminalSettings UI, not by editing ghostty config files.

5. **Event loop integration** — `wakeup_cb` posts to `DispatchQueue.main`, which calls `ghostty_app_tick()`. No separate run loop needed.

6. **PTY is internal** — libghostty manages PTY creation, command execution, and I/O. We pass command + working directory in surface config.

7. **Graceful surface destruction** — Before calling `ghostty_surface_free()`, send `tmux detach-client` to allow tmux to detach cleanly rather than receiving SIGHUP. This preserves tmux session state during LRU cache eviction.

8. **TERM environment** — Verify libghostty's default TERM value. If it differs from `xterm-256color`, override via env vars in surface config to maintain tmux compatibility.

### Components

- **`GhosttyApp`** — Singleton managing `ghostty_app_t` lifecycle, runtime callbacks, tick scheduling
- **`GhosttyAdapter`** — `TerminalHost` implementation wrapping surface lifecycle
- **`GhosttySurfaceView`** — NSView subclass hosting the ghostty surface (key/mouse event forwarding, IME, Retina scaling)
- **`ColorHelpers.swift`** — `NSColor(hex:)` extension extracted from SwiftTermAdapter
- **`build-ghostty.sh`** — Script to clone Ghostty repo and build XCFramework via Zig
- **mise task** — `mise run build:ghostty` to rebuild XCFramework

## Implementation Phases

### Phase 0: API Verification (research spike)

1. Clone Ghostty repository, check out pinned commit (files: `scripts/build-ghostty.sh`)
2. Read `include/ghostty.h` — verify all C API function names, struct layouts, and callback signatures
3. Document verified API surface in this plan's Review Feedback section:
   - App lifecycle: init, app_new, app_free, app_tick
   - Surface lifecycle: surface_new, surface_free
   - Input: surface_key, surface_mouse_button, surface_mouse_pos, surface_text
   - Config: how to set font, colors, cursor, TERM env var
   - Surface config struct: exact fields for command, working_directory, env_vars, platform
4. Verify hot-reload support: can config be applied to a live surface, or only at creation time?
5. Verify TERM env var handling: what does libghostty set by default?
6. Verify Zig version requirement from `build.zig.zon`
7. Update this plan with corrected API names if they differ from initial assumptions

### Phase 1: Build Infrastructure (toolchain + XCFramework)

1. Add Zig (pinned version from Phase 0) to mise tool versions (files: `mise.toml`)
2. Create `scripts/build-ghostty.sh` — clones ghostty repo at pinned commit, builds XCFramework, copies to `Frameworks/` (files: `scripts/build-ghostty.sh`)
3. Add `build:ghostty` mise task (files: `mise.toml`)
4. Run the build script and verify `Frameworks/GhosttyKit.xcframework` is produced with `include/ghostty.h` header and module map
5. Add `Frameworks/` to `.gitignore` (files: `.gitignore`)

### Phase 2: Package Integration (SPM + module map)

1. Update `Packages/MoriTerminal/Package.swift` — remove SwiftTerm dependency, add GhosttyKit dependency (files: `Packages/MoriTerminal/Package.swift`)
   - Option A: `.binaryTarget(name: "GhosttyKit", path: "../../Frameworks/GhosttyKit.xcframework")` — test if SPM accepts the `../../` path
   - Option B (fallback): Declare `.binaryTarget` in root `Package.swift`, pass as dependency to MoriTerminal
   - Option C (fallback): Symlink or copy XCFramework into `Packages/MoriTerminal/Frameworks/`
2. Verify the XCFramework includes a module map. If not, create one at `Packages/MoriTerminal/Sources/MoriTerminal/GhosttyBridge/module.modulemap` with umbrella header pointing to `ghostty.h` (files: `Packages/MoriTerminal/Sources/MoriTerminal/GhosttyBridge/`)
3. Create stub `GhosttyAdapter.swift` with `import GhosttyKit` (or the module name from the XCFramework) and verify compilation (files: `Packages/MoriTerminal/Sources/MoriTerminal/GhosttyAdapter.swift`)
4. Update root `Package.swift` if Option B is needed (files: `Package.swift`)

### Phase 3: GhosttyApp Singleton + Config Helpers

1. Create `GhosttyApp.swift` — `@MainActor` class owning the app-level ghostty context (files: `Packages/MoriTerminal/Sources/MoriTerminal/GhosttyApp.swift`)
   - Init: initialize runtime, build runtime config with callbacks, create app
   - Deinit: free app
   - Tick: wakeup callback -> `DispatchQueue.main.async` -> app tick
   - Runtime callbacks: clipboard read/write (NSPasteboard), wakeup, action handler
   - Config builder: write temp config file from `TerminalSettings`, load via `ghostty_config_load_file()`, then `ghostty_config_finalize()`
   - Use `Unmanaged<GhosttyApp>.passUnretained(self).toOpaque()` for callback userdata
2. Config file writer (files: `Packages/MoriTerminal/Sources/MoriTerminal/GhosttyConfigWriter.swift`)
   - `writeConfig(settings: TerminalSettings) -> URL` — writes temp file at `~/Library/Application Support/Mori/ghostty.conf`
   - Key mappings: font-family, font-size, background/foreground (hex without #), cursor-color, selection-background, palette 0-15, term=xterm-256color
   - `CursorStyle.block` -> `cursor-style = block`, etc.
3. Unit tests for config translation helpers (files: MoriTerminal test target)

### Phase 4: GhosttyAdapter + SurfaceView

1. Create `GhosttySurfaceView.swift` — NSView subclass for hosting (files: `Packages/MoriTerminal/Sources/MoriTerminal/GhosttySurfaceView.swift`)
   - `wantsLayer = true`, CALayer with `contentsScale = backingScaleFactor`
   - `acceptsFirstResponder` -> true
   - Forward key events via ghostty surface key API
   - Forward mouse events (button, position, scroll) via ghostty surface mouse API
   - `NSTextInputClient` conformance for IME support
   - Store `ghostty_surface_t` reference for event forwarding
2. Create `GhosttyAdapter.swift` implementing `TerminalHost` (files: `Packages/MoriTerminal/Sources/MoriTerminal/GhosttyAdapter.swift`)
   - `createSurface(command:workingDirectory:)`: create GhosttySurfaceView, build surface config (command, workdir, font_size, env vars with TERM=xterm-256color), create ghostty surface, store view<->surface mapping
   - `destroySurface(_:)`: send "tmux detach-client" escape sequence first for graceful tmux detach, then free ghostty surface, remove from mapping
   - `surfaceDidResize(_:to:)`: notify ghostty of new size (or rely on CALayer auto-resize if supported)
   - `focusSurface(_:)`: `window.makeFirstResponder(view)` + notify ghostty of focus
   - `applySettings(to:)`: if hot-reload supported -> apply config to live surface; if not -> log warning (settings apply on next surface creation)
3. Environment helper (files: `Packages/MoriTerminal/Sources/MoriTerminal/GhosttyAdapter.swift`)
   - Build env vars: TERM=xterm-256color, LANG=en_US.UTF-8, HOME

### Phase 5: Swap Default + Remove SwiftTerm

1. Extract `NSColor(hex:)` to `Packages/MoriTerminal/Sources/MoriTerminal/ColorHelpers.swift` (files: `Packages/MoriTerminal/Sources/MoriTerminal/ColorHelpers.swift`)
   - Consumers: `AppDelegate.swift`, `TerminalAreaViewController.swift`, `MainWindowController.swift` (app target imports MoriTerminal, so public extension is accessible)
   - Also used by `GhosttyApp.swift` config helpers
2. Update `TerminalAreaViewController` default init: `SwiftTermAdapter()` -> `GhosttyAdapter()` (files: `Sources/Mori/App/TerminalAreaViewController.swift`)
3. Delete `SwiftTermAdapter.swift` entirely (TerminalScrollFix, TerminalPasteFix, swiftTermColor helper) — commit separately for clean revert (files: `Packages/MoriTerminal/Sources/MoriTerminal/SwiftTermAdapter.swift`)
4. Remove SwiftTerm from `Package.resolved` by running `swift package resolve` (files: `Package.resolved`)
5. Verify build: `mise run build` with zero warnings
6. Verify all tests pass: `mise run test`

### Phase 6: Integration Testing + Polish

1. Manual smoke test: launch app, attach to tmux session, verify rendering
2. Test font/theme/cursor changes via Settings UI
3. Test scroll wheel in tmux (mouse mode on)
4. Test paste (small and large > 1KB)
5. Test surface cache (switch between 4+ worktrees, verify LRU eviction)
6. Test empty state -> attach -> detach flow
7. Test graceful destroySurface: evict from cache, verify tmux session survives
8. Fix any issues discovered during testing
9. Update CLAUDE.md architecture notes (SwiftTerm -> libghostty, remove GhosttyAdapter mention as "drop-in replacement when Xcode available")

## Testing Strategy

- **Build verification**: `mise run build` succeeds, zero warnings
- **Existing tests**: `mise run test` — all existing tests pass (they don't depend on SwiftTerm directly)
- **New unit tests**: Config translation helpers (hex->color, cursor mapping, palette translation)
- **Manual integration tests**: Launch app, exercise all terminal workflows
- **Regression checklist**:
  - tmux attach-session works
  - Colors render correctly (ANSI 16 palette + true color)
  - Font changes apply immediately
  - Cursor style changes apply
  - Mouse scroll works in tmux
  - Large paste doesn't truncate
  - Window resize updates terminal dimensions
  - Surface cache LRU eviction works (tmux sessions survive eviction)
  - Cmd+C/V copy/paste works
  - IME input works (e.g., CJK characters)

## Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| libghostty API is unstable/undocumented | High | Phase 0 verifies actual API; pin to specific commit; reference Ghostty's own macOS app |
| API names in plan are wrong | High | Phase 0 corrects them before any code is written |
| XCFramework build fails | Medium | Document exact Zig version; build script is idempotent; provide pre-built binary option |
| SPM binaryTarget path escapes package dir | Medium | Three fallback options documented in Phase 2 |
| Zig toolchain not available via mise | Low | Fallback: `brew install zig` with pinned version |
| libghostty C header not accessible from Swift | Medium | Create explicit module.modulemap if XCFramework doesn't include one |
| GPU rendering requires Metal — may not work in CI | Low | Out of scope; NativeTerminalAdapter remains as fallback |
| ghostty_config doesn't support hot-reload | Medium | Log warning; settings apply on next surface creation; document gap |
| TERM env var mismatch breaks tmux | Medium | Phase 0 verifies; override in surface config env vars |
| ghostty_surface_free sends SIGHUP to tmux | Medium | Send tmux detach-client first for graceful cleanup |
| Large XCFramework binary (~50MB+) | Medium | .gitignore; rebuild via `mise run build:ghostty` |

## Open Questions

(All resolved — see Assumptions, Phase 0, and Verified API section)

## Verified API (Phase 0 findings)

**Ghostty commit**: `c9e1006213eb9234209924c91285d6863e59ce4c` (tip-of-tree, version 1.3.2-dev)
**Zig version required**: `0.15.2` (from `build.zig.zon`, confirmed available via `mise ls-remote zig`)

### App Lifecycle (confirmed)
- `ghostty_init(argc, argv)` -> int (GHOSTTY_SUCCESS = 0)
- `ghostty_config_new()` -> `ghostty_config_t?`
- `ghostty_config_load_default_files(config)` — loads from ~/.config/ghostty/
- `ghostty_config_load_file(config, path)` — loads from specific file (key=value format)
- `ghostty_config_finalize(config)` — populates defaults
- `ghostty_config_get(config, ptr, key, key_len)` -> bool — read config values
- `ghostty_config_free(config)`
- `ghostty_app_new(runtime_config, config)` -> `ghostty_app_t?`
- `ghostty_app_tick(app)` — process events
- `ghostty_app_update_config(app, config)` — **hot-reload config on app level**
- `ghostty_app_free(app)`

### Surface Lifecycle (confirmed)
- `ghostty_surface_config_new()` -> `ghostty_surface_config_s` — default surface config
- `ghostty_surface_new(app, surface_config)` -> `ghostty_surface_t?`
- `ghostty_surface_free(surface)` — destroy surface
- `ghostty_surface_update_config(surface, config)` — **hot-reload config on surface level** (confirmed!)
- `ghostty_surface_set_size(surface, width_px, height_px)` — resize
- `ghostty_surface_set_focus(surface, bool)` — focus notification
- `ghostty_surface_set_content_scale(surface, x, y)` — Retina scaling
- `ghostty_surface_refresh(surface)` — refresh display
- `ghostty_surface_draw(surface)` — render
- `ghostty_surface_request_close(surface)` — graceful close request

### Surface Config Struct (confirmed)
```c
ghostty_surface_config_s {
  platform_tag: GHOSTTY_PLATFORM_MACOS
  platform.macos.nsview: void*  // raw NSView pointer
  userdata: void*
  scale_factor: double
  font_size: float
  working_directory: const char*
  command: const char*
  env_vars: ghostty_env_var_s*  // array of {key, value} pairs
  env_var_count: size_t
  initial_input: const char*
  wait_after_command: bool
  context: GHOSTTY_SURFACE_CONTEXT_WINDOW
}
```

### Input (confirmed)
- `ghostty_surface_key(surface, key_input)` -> bool
- `ghostty_surface_text(surface, text, len)` — IME text input
- `ghostty_surface_preedit(surface, text, len)` — IME preedit
- `ghostty_surface_mouse_button(surface, state, button, mods)` -> bool
- `ghostty_surface_mouse_pos(surface, x, y, mods)`
- `ghostty_surface_mouse_scroll(surface, x, y, scroll_mods)`
- `ghostty_surface_ime_point(surface, &x, &y, &w, &h)` — get IME position

### Runtime Config (callbacks)
```c
ghostty_runtime_config_s {
  userdata: void*
  supports_selection_clipboard: bool
  wakeup_cb: (void*) -> void
  action_cb: (app, target, action) -> bool
  read_clipboard_cb: (void*, clipboard_type, state) -> bool
  confirm_read_clipboard_cb: (void*, text, state, request_type) -> void
  write_clipboard_cb: (void*, clipboard_type, content*, count, confirm) -> void
  close_surface_cb: (void*, bool) -> void
}
```

### Config Approach (revised from plan)
**No programmatic "set key=value" API exists.** Config is loaded from:
1. Default files (`ghostty_config_load_default_files`)
2. Specific file path (`ghostty_config_load_file`) — file uses `key = value` format
3. CLI args (`ghostty_config_load_cli_args`)

**Strategy for Mori**: Write a temporary config file with our settings, load it via `ghostty_config_load_file()`. Key config keys:
- `font-family = "SF Mono"`
- `font-size = 13`
- `background = 1e1e1e` (no # prefix, RGB hex)
- `foreground = d4d4d4`
- `cursor-color = aeafad`
- `selection-background = 264f78`
- `palette = 0=#000000` through `palette = 15=#ffffff`
- `term = xterm-256color` (overrides default `xterm-ghostty` for tmux compat)

### TERM Default (confirmed)
Default is `xterm-ghostty`. **Must override to `xterm-256color`** for tmux compatibility, either via config file `term = xterm-256color` or via `env_vars` in surface config.

### Hot-Reload (confirmed)
`ghostty_surface_update_config(surface, new_config)` exists and is used by Ghostty's macOS app. **applySettings() can work by building a new config and calling this.**

### XCFramework Build
```bash
zig build -Demit-xcframework=true -Dapp-runtime=none -Doptimize=ReleaseFast
```
XCFramework includes `module.modulemap` as `GhosttyKit` module with umbrella header `ghostty.h`.

### Module Map (already included)
```
module GhosttyKit {
    umbrella header "ghostty.h"
    export *
}
```
No custom module map needed — the XCFramework ships with one.

## Review Feedback

### Round 1 (reviewer)

Issues addressed:
1. **NSColor(hex:) relocation** — Specified: moves to `ColorHelpers.swift` in MoriTerminal. Consumers listed: AppDelegate, TerminalAreaViewController, MainWindowController (all in app target which imports MoriTerminal).
2. **API verification** — Added Phase 0: clone Ghostty, read ghostty.h, verify/correct all API names before coding.
3. **SPM binaryTarget path** — Documented 3 fallback options (../../ relative, root Package.swift, symlink/copy).
4. **destroySurface semantics** — Added graceful tmux detach-client before ghostty_surface_free.
5. **TERM env var** — Added to Phase 0 verification; default override to xterm-256color in surface config.
6. **applySettings hot-reload** — Added to Phase 0 verification; fallback documented if not supported.
7. **Zig version pinning** — Determined from Ghostty's build.zig.zon in Phase 0.
8. **Unit tests** — Added to Phase 3 for config translation helpers.
9. **Rollback strategy** — Documented: git revert the deletion + swap commits.

## Final Status

(Updated after implementation completes)
