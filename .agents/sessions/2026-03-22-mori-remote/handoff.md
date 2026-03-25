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

### Phase 5A: iOS App — ghostty Rendering + Pipe Bridge (2026-03-25)

**Status**: COMPLETE (8/8 tasks)

**What was done**:
- Updated `project.yml` to add MoriRemoteProtocol SPM dependency
- Enhanced `MoriRemoteApp.swift` with scenePhase lifecycle observer, dark color scheme, status bar hidden
- Created `GhosttyRemoteSurface.swift` — UIView subclass that configures ghostty surface with `remote_read_fd`/`remote_write_fd` for the Remote termio backend
- Created `PipeBridge.swift` — actor managing two `pipe()` fd pairs for bidirectional data flow between ghostty and external sources (future WebSocket)
- Rewrote `TerminalView.swift` to use `GhosttyRemoteSurfaceView` with PipeBridge, safe area handling (ignores top + keyboard), canned VT byte test
- Created `InputAccessoryBar.swift` — UIKit accessory view with Esc, Ctrl (toggle), Tab, pipe, tilde, dash, slash, arrow keys
- Built universal XCFramework (macOS + iOS + iOS Sim) and verified both iOS simulator and macOS builds pass
- Zero Swift compilation errors in MoriRemote code (GhosttyKit umbrella header warnings are upstream)

**Files changed**:
- `MoriRemote/project.yml` — added MoriRemoteProtocol package dependency
- `MoriRemote/MoriRemote/MoriRemoteApp.swift` — lifecycle + MoriRemoteProtocol import
- `MoriRemote/MoriRemote/GhosttyRemoteSurface.swift` — new: Remote backend surface view
- `MoriRemote/MoriRemote/PipeBridge.swift` — new: bidirectional pipe bridge actor
- `MoriRemote/MoriRemote/TerminalView.swift` — rewritten: Remote backend + safe areas
- `MoriRemote/MoriRemote/InputAccessoryBar.swift` — new: terminal key accessory bar

**Commits**:
- `67be726` — 5A.1+5A.2: Link MoriRemoteProtocol + enhance iOS app lifecycle
- `5b40c68` — 5A.4: GhosttyRemoteSurface UIView with pipe fd pair
- `a57ae2c` — 5A.5: PipeBridge for bidirectional ghostty <-> network data flow
- `4beb13d` — 5A.6: Terminal view with Remote backend + safe area handling
- `2d1879f` — 5A.7: Terminal input accessory bar (Ctrl, Esc, Tab, arrows)

**Key learnings**:
- `pipe()` syscall works in iOS sandbox — creates fd pairs within the same process
- ghostty Remote backend activated when `remote_read_fd >= 0` in surface config
- Universal XCFramework slice path is `macos-arm64_x86_64` (not `macos-arm64`) — SPM resolves automatically but cached `.build` may need cleaning
- PipeBridge uses non-blocking I/O on read end + async polling for Swift 6 concurrency compatibility
- Input accessory bar needs UIScrollView for horizontal key list to work across device sizes

**Context for next phase** (Phase 5B: iOS App — WebSocket Client + Reconnect):
- PipeBridge has `onInputFromGhostty` callback ready for WebSocket forwarding
- PipeBridge.writeToTerminal() accepts Data for writing to ghostty's read pipe
- MoriRemoteProtocol is linked and importable — ControlMessage types ready for WebSocket framing
- scenePhase observer in MoriRemoteApp ready for background detach / foreground reconnect
- InputAccessoryBar.onKeyPress sends raw bytes — needs to be wired to PipeBridge in terminal view

### Phase 5B: iOS App — WebSocket Client + Reconnect (2026-03-25)

**Status**: COMPLETE (5/5 tasks)

**What was done**:
- Created `RelayClient` actor: URLSessionWebSocketTask-based WebSocket client connecting to relay as viewer role
  - Implements MoriRemoteProtocol state machine (disconnected -> pairing -> connected -> attached -> detached)
  - Binary frames for terminal data, JSON text frames for control messages
  - Automatic reconnection with exponential backoff (1s base, 30s max, 10 attempts, jitter)
  - Session ID extraction from handshake capabilities (same pattern as MoriRemoteHost RelayConnector)
  - Heartbeat response: echoes relay ping timestamps back as pong
  - Handles token_expired/token_invalid errors by invalidating session and requiring re-pair
- Updated `MoriRemoteApp.swift` with iOS lifecycle handling:
  - scenePhase .background: immediately disconnects relay (no background keep-alive)
  - scenePhase .active: reconnects using stored session ID if was previously connected
  - Tracks `wasConnectedBeforeBackground` state for clean lifecycle transitions
- Created `KeychainStore`: Security.framework wrapper for session ID persistence
  - `kSecAttrAccessibleAfterFirstUnlock` for availability during foreground reconnect
  - save/load/delete operations for session lifecycle
  - Invalidation clears credential, forcing re-pairing
- Updated `TerminalView` to wire PipeBridge <-> RelayClient bidirectionally:
  - Relay binary data -> PipeBridge.writeToTerminal() -> ghostty renders
  - PipeBridge.onInputFromGhostty -> RelayClient.sendTerminalData() -> relay
- Updated `PipeBridge` callback to `async throws` for WebSocket forwarding compatibility
- Created reconnect state machine tests (61 assertions):
  - Valid/invalid ConnectionState transitions
  - Disconnect + reconnect scenario
  - Background/foreground lifecycle (detach -> disconnect -> reconnect -> re-attach)
  - Session expiry + re-pair from scratch
  - Detach and switch session flow
  - ControlMessage serialization round-trip for all 8 message types
  - Heartbeat timestamp preservation, ErrorCode round-trip

**Files created/changed**:
- `MoriRemote/MoriRemote/RelayClient.swift` — new: WebSocket client actor
- `MoriRemote/MoriRemote/KeychainStore.swift` — new: Keychain wrapper
- `MoriRemote/MoriRemote/MoriRemoteApp.swift` — updated: lifecycle + RelayClient integration
- `MoriRemote/MoriRemote/TerminalView.swift` — updated: RelayClient + PipeBridge wiring
- `MoriRemote/MoriRemote/PipeBridge.swift` — updated: async throws callback
- `Packages/MoriRemoteProtocol/Package.swift` — added test target
- `Packages/MoriRemoteProtocol/Tests/TestMoriRemoteProtocol/` — new: 61-assertion test suite

**Commits**:
- `f31d976` — 5B.1: RelayClient WebSocket actor with MoriRemoteProtocol state machine
- `5d31f96` — 5B.2: iOS lifecycle handling (detach on background, reconnect on foreground)
- `2b1b1f1` — 5B.3: KeychainStore for session ID persistence with invalidation
- `ba3fe37` — 5B.4+5B.5: Heartbeat response + reconnect state machine tests (61 assertions)

**Key learnings**:
- URLSessionWebSocketTask handles WebSocket ping/pong at the transport level automatically; application-level heartbeat is a separate JSON control message
- PipeBridge callback needs to be `async throws` (not just `@Sendable (Data) -> Void`) because WebSocket sends are async and can fail
- KeychainStore uses `kSecAttrAccessibleAfterFirstUnlock` (not `kSecAttrAccessibleWhenUnlocked`) so it's available during the brief foreground transition period
- ConnectionState.transition(to:) returns nil for invalid transitions — RelayClient logs but doesn't crash

**Context for next phase** (Phase 6: iOS App — Session List + QR Pairing + Mode Toggle):
- RelayClient is fully functional with connect/reconnect/disconnect/sendControlMessage/sendTerminalData
- RelayClient.onControlMessage callback delivers parsed ControlMessage to the UI layer
- RelayClient.onStateChange callback delivers ConnectionState changes for status indicators
- KeychainStore.loadSessionID() returns stored session for automatic reconnection
- Phase 6 needs: QR scanner (AVCaptureSession), session list view, mode toggle, connection status UI
- RelayClient.invalidateSession() clears Keychain + saved URLs for "Forget this device" flow
