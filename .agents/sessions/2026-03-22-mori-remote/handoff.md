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

### Phase 4: Mac Relay Connector — MoriRemoteHost (2026-03-25)

**Status**: COMPLETE (8/8 tasks)

**What was done**:
- Added `MoriRemoteHost` executable target to root Package.swift (depends on MoriRemoteProtocol, MoriTmux, swift-argument-parser)
- CLI with 4 subcommands: `serve`, `sessions`, `qrcode`, `loopback`
- `RelayConnector` actor: outbound WSS to relay as host, handles control messages (attach, detach, resize, mode change, heartbeat, session list), bidirectional byte streaming
- `PTYBridge`: uses `forkpty()` to spawn `tmux attach-session`, provides read/write to pty master, handles resize via `TIOCSWINSZ`, monitors child exit
- `SessionLister`: lists tmux sessions via TmuxCommandRunner + TmuxParser, maps to SessionInfo with display-friendly names using `SessionNaming.parse()`
- `GroupedSessionManager` actor: creates grouped sessions (`tmux new-session -t <target>`) for interactive mode, tracks active sessions, cleans up on disconnect, runs periodic GC (60s) to remove stale sessions
- `QRCodeGenerator`: CoreImage CIQRCodeGenerator for PNG and ASCII terminal QR output; `qrcode` subcommand can request tokens from relay `/pair` endpoint
- `SessionIDStore`: persists session IDs to `~/Library/Application Support/Mori/remote-session-id` for cross-restart reconnection with TTL (120s default)
- Exponential backoff reconnection: 1s base, 60s max, 10 attempts, jitter
- `LoopbackRelay`: in-process Network.framework WebSocket relay for local testing; `LoopbackHarness` runs e2e test (relay + connector + session listing)
- Full project builds cleanly (zero warnings, zero errors)

**Files changed**:
- `Package.swift` — added MoriRemoteProtocol dependency + MoriRemoteHost target
- `Sources/MoriRemoteHost/MoriRemoteHost.swift` — CLI entry point
- `Sources/MoriRemoteHost/Commands/Serve.swift` — serve subcommand
- `Sources/MoriRemoteHost/Commands/Sessions.swift` — sessions subcommand
- `Sources/MoriRemoteHost/Commands/QRCode.swift` — qrcode subcommand
- `Sources/MoriRemoteHost/Commands/Loopback.swift` — loopback subcommand
- `Sources/MoriRemoteHost/RelayConnector.swift` — relay connection actor
- `Sources/MoriRemoteHost/PTYBridge.swift` — forkpty bridge
- `Sources/MoriRemoteHost/SessionLister.swift` — session listing with SessionNaming
- `Sources/MoriRemoteHost/GroupedSessionManager.swift` — grouped session lifecycle + GC
- `Sources/MoriRemoteHost/QRCodeGenerator.swift` — QR code generation
- `Sources/MoriRemoteHost/SessionIDStore.swift` — session ID persistence
- `Sources/MoriRemoteHost/LoopbackRelay.swift` — loopback relay + test harness

**Commits**:
- `0c3a183` — 4.1: MoriRemoteHost executable target with CLI subcommands
- `ac755ff` — 4.2: RelayConnector actor with forkpty and bidirectional pipe
- `151e00c` — 4.3: Session listing with SessionNaming.parse()
- `1f095a5` — 4.4+4.5: Grouped session support with cleanup and periodic GC
- `c868325` — 4.6: QR code generation using CoreImage
- `2389307` — 4.7: Reconnection with exponential backoff and session ID persistence
- `afc2716` — 4.8: Relay-free loopback harness

**Context for next phase** (Phase 5A: iOS App — ghostty Rendering + Pipe Bridge):
- MoriRemoteHost is fully functional as a standalone process that can bridge tmux sessions to a WebSocket relay
- The LoopbackRelay in MoriRemoteHost can be used to test iOS client -> relay -> host without deploying the Go relay
- PTYBridge demonstrates the forkpty pattern that the iOS side mirrors with pipe fd pairs (read/write instead of pty)
- SessionInfo type from MoriRemoteProtocol is used consistently between host and iOS for session display
- The relay protocol is JSON text frames for control + binary frames for terminal data (already implemented in RelayConnector)
