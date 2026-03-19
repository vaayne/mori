# Tasks: Replace SwiftTerm with libghostty

## Phase 0: API Verification (research spike)

- [x] 0.1 — Clone Ghostty repository, identify latest stable tag/commit
- [x] 0.2 — Read `include/ghostty.h`, document verified API surface (app lifecycle, surface lifecycle, input, config)
- [x] 0.3 — Verify hot-reload support for config on live surfaces (confirmed: `ghostty_surface_update_config`)
- [x] 0.4 — Verify TERM env var default and override mechanism (default: `xterm-ghostty`, override via config `term = xterm-256color`)
- [x] 0.5 — Identify required Zig version from `build.zig.zon` (Zig 0.15.2)
- [x] 0.6 — Update plan with verified API names and config approach (config file, not programmatic setter)

## Phase 1: Build Infrastructure (toolchain + XCFramework)

- [x] 1.1 — Add Zig 0.15.2 to `mise.toml`
- [x] 1.2 — Create `scripts/build-ghostty.sh` (clone at commit c9e1006, build XCFramework, copy to `Frameworks/`)
- [x] 1.3 — Add `build:ghostty` mise task (`mise.toml`)
- [x] 1.4 — Run build script, verify XCFramework output with `ghostty.h` header + GhosttyKit module map
- [x] 1.5 — Add `Frameworks/` to `.gitignore`

## Phase 2: Package Integration (SPM + module map)

- [x] 2.1 — Update `Packages/MoriTerminal/Package.swift` — remove SwiftTerm, add GhosttyKit binaryTarget
- [x] 2.2 — Verify XCFramework includes module map (confirmed: GhosttyKit module). No bridging needed.
- [x] 2.3 — Create stub `GhosttyAdapter.swift` with `import GhosttyKit`, verify compilation
- [x] 2.4 — Root `Package.swift` unchanged (binaryTarget in MoriTerminal with ../../ path works)

## Phase 3: GhosttyApp Singleton + Config Writer

- [x] 3.1 — Create `GhosttyApp.swift` — @MainActor singleton owning ghostty app context, runtime callbacks
- [x] 3.2 — Create `GhosttyConfigWriter.swift` — write TerminalSettings to temp ghostty config file
- [ ] 3.3 — Unit tests for config writer output (deferred to Phase 6)

## Phase 4: GhosttyAdapter + SurfaceView

- [x] 4.1 — Create `GhosttySurfaceView.swift` — NSView subclass with key/mouse forwarding, IME, Retina
- [x] 4.2 — Create `GhosttyAdapter.swift` implementing TerminalHost (createSurface, destroySurface, resize, focus, applySettings)
- [x] 4.3 — Environment helper: TERM=xterm-256color, LANG, HOME (inline in createSurface)

## Phase 5: Swap Default + Remove SwiftTerm

- [x] 5.1 — Extract `NSColor(hex:)` to `ColorHelpers.swift`
- [x] 5.2 — Update `TerminalAreaViewController` default: `SwiftTermAdapter()` -> `GhosttyAdapter()`
- [x] 5.3 — Delete `SwiftTermAdapter.swift`
- [x] 5.4 — Remove SwiftTerm from Package.resolved
- [x] 5.5 — Verify build: `swift build` succeeds (2 harmless ImGui warnings)
- [x] 5.6 — Verify tests: `mise run test` all 553 assertions pass

## Phase 6: Integration Testing + Polish

- [ ] 6.1 — Smoke test: launch app, attach tmux session, verify rendering
- [ ] 6.2 — Test font/theme/cursor settings changes
- [ ] 6.3 — Test scroll wheel in tmux (mouse mode on)
- [ ] 6.4 — Test paste (small + large > 1KB)
- [ ] 6.5 — Test surface cache LRU eviction (4+ worktrees)
- [ ] 6.6 — Test empty state -> attach -> detach flow
- [ ] 6.7 — Test graceful destroySurface (tmux session survives eviction)
- [ ] 6.8 — Fix issues discovered during testing
- [ ] 6.9 — Update CLAUDE.md architecture notes
