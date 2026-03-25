# Handoff: Mori Remote

## Project

iOS companion app + cloud relay for remote tmux terminal interaction via libghostty.

## Plan

See [plan.md](plan.md) for full details.

## Phase Log

### Phase 1: Fork Ghostty + Universal Build + iOS Proof-of-Life (2026-03-25)

**Status**: COMPLETE (10/11 tasks, docs pending)

**What was done**:
- Forked ghostty-org/ghostty -> vaayne/ghostty
- Updated .gitmodules to point to fork, added upstream remote
- Created `mori/remote-backend` branch in fork, pushed to origin
- Updated `scripts/build-ghostty.sh`: universal by default (macOS + iOS + iOS Sim), `--native` fallback, auto-detects iphoneos SDK
- Built universal XCFramework with 3 slices (macOS arm64+x86_64, iOS arm64, iOS Sim arm64)
- Verified Mori macOS still builds with universal framework
- Created `MoriRemote/` iOS shell app (XcodeGen project):
  - `MoriRemoteApp.swift` — SwiftUI @main, calls ghostty_init()
  - `GhosttyAppContext.swift` — singleton managing ghostty_app_t, runtime callbacks
  - `GhosttySurfaceUIView.swift` — UIView with CAMetalLayer, creates ghostty surface
  - `TerminalView.swift` — SwiftUI UIViewRepresentable wrapper
- iOS simulator build passes (iPhone 16, iOS 18.2)

**Key learnings**:
- Zig's HTTP client fails through local proxies (Surge/ClashX) — need direct connection for `zig build`
- XCFramework includes module.modulemap per slice — use `import GhosttyKit` directly, no bridging header needed
- Swift 6 strict concurrency: use `nonisolated(unsafe)` for surface pointer accessed in deinit
- ghostty has no `ghostty_config_load_string` API — write overrides to temp file

**Commits**: `826f61b` (fork + build script)
