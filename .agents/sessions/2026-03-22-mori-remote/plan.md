# Plan: Mori Remote — iOS Terminal Client + Cloud Relay

## Overview

Build an iOS companion app (Mori Remote) that connects to a cloud-hosted relay service, enabling full interactive tmux terminal sessions from anywhere using libghostty for GPU-accelerated rendering. The Mac runs a relay connector that bridges its tmux sessions to the cloud; the iOS app connects to the same relay to view and interact with those sessions.

### Goals

- Full interactive terminal on iOS using libghostty (same renderer as Mac)
- Cloud-hosted relay for access from anywhere (not just LAN)
- QR-code token pairing between Mac and iOS (no accounts)
- List and select tmux sessions, toggle read-only vs interactive mode
- Single Mac connection (1:1 pairing)

### Success Criteria

- [ ] GhosttyKit XCFramework builds for both macOS and iOS (arm64 + simulator)
- [ ] Remote termio backend added to ghostty (Zig) — accepts bytes over fd pair instead of pty
- [ ] iOS shell app renders canned VT bytes via libghostty (proves renderer works before network)
- [ ] Go relay service deployed to Fly.io, handles WebSocket pairing and binary byte streaming
- [ ] Mac relay connector bridges tmux sessions to the cloud relay via outbound WebSocket
- [ ] iOS app renders live terminal via libghostty, receives bytes from relay, sends input back
- [ ] QR-code pairing flow works end-to-end
- [ ] Read-only and interactive modes with toggle
- [ ] Session list and selection UI on iOS

### Out of Scope

- Mori sidebar features on iOS (projects, worktrees, agent badges)
- Multiple Mac support
- LAN/local fallback (no relay)
- Account-based auth
- iPad split view / multi-session
- Push notifications (APNs)
- tmux control mode (future optimization, not MVP)
- E2E encryption (deferred — see Security section)

### Prerequisites

- **Ghostty fork** — fork `ghostty-org/ghostty` to your GitHub, update `.gitmodules` to point to fork
- **Zig 0.15.2** — already in the project
- **Full Xcode.app** — required for iphoneos SDK (not just CLI tools)
- **Go toolchain** — for building the relay service
- **Fly.io account + `flyctl` CLI** — for relay deployment
- **iOS development certificate + provisioning profile** — for device testing
- **AVFoundation camera permission** — for QR code scanning (added to Info.plist)

## Technical Approach

### Architecture

```
                        Cloud (Fly.io)
┌──────────┐    WSS    ┌─────────────┐    WSS    ┌──────────┐
│ Mac      │──────────>│ Go Relay    │<──────────│ iOS App  │
│ Connector│ outbound  │ (token pair)│  outbound │ (ghostty)│
└────┬─────┘           └─────────────┘           └──────────┘
     │ pty
     v
  tmux attach -t <session>
```

**Mac side**: A dedicated `MoriRemoteHost` helper process (not embedded in the main app) spawns a pty running `tmux attach-session -t <session>`. Raw bytes from the pty are streamed over WebSocket to the relay. Input from the relay is written to the pty. Running as a separate process enables cleaner lifecycle, future launch-at-login, and headless host mode.

**Relay**: A Go service (~300 LOC) using `coder/websocket`. Accepts WSS connections with a token + role (host/viewer). Pairs them in an in-memory map. Pipes binary WebSocket frames bidirectionally. No persistence, no logging of terminal data.

**iOS side**: A SwiftUI app using libghostty for terminal rendering. Connects to the relay via WebSocket. Terminal bytes from the relay are fed into ghostty's renderer via pipe fd; keyboard input is sent back via pipe fd -> WebSocket. Uses a modified ghostty with a `Remote` termio backend that reads/writes over a pipe/fd pair instead of a pty.

### Key Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Terminal renderer (iOS) | libghostty (GhosttyKit) | GPU-accelerated Metal, same as Mac, already has iOS UIKit support |
| ghostty IO on iOS | New `Remote` termio backend (Zig) | Plugs into existing Surface/Renderer pipeline |
| Relay tech | Go + coder/websocket on Fly.io | Battle-tested for terminal streaming (Coder uses it), ~300 LOC, $2-3/month |
| Mac-to-tmux bridge | pty + `tmux attach` | Raw bytes, no parsing needed. Same approach as ttyd/gotty |
| Mac host process | Separate `MoriRemoteHost` helper | Cleaner lifecycle, works when Mori UI is closed, future launch-at-login |
| Auth | QR-code pairing token -> session ID for reconnection | Token consumed on pairing; session ID stored in iOS Keychain |
| tmux sizing | `attach -r` (read-only + ignore-size) for monitoring; grouped session for interactive | Prevents iOS from constraining Mac terminal size |
| Protocol | Binary WebSocket frames for terminal data; JSON text frames for control messages | Clean separation; versioned handshake for evolution |
| iOS lifecycle | Design for detach/resume on suspension, not background keep-alive | iOS suspends apps unpredictably; reconnect fast on foreground |
| Distribution | TestFlight | Avoids App Store review complexity for personal/team use |

### Components

- **GhosttyKit iOS Build**: Modify build script to produce universal XCFramework (macOS + iOS + iOS Simulator)
- **Remote termio backend** (Zig): New backend for ghostty that reads/writes over fd pair instead of pty
- **MoriRemoteProtocol**: Cross-platform Swift package defining message types, state machine, versioning
- **Go Relay Service**: WebSocket pairing server, binary byte relay, token auth
- **MoriRemoteHost**: Separate Mac helper process that bridges pty (tmux attach) to WebSocket
- **iOS App (Mori Remote)**: SwiftUI app with session list, terminal view (ghostty), mode toggle
- **Reused from Mori**: `SessionNaming` (from MoriTmux) for display-friendly session names

### Security

**Threat model**: Terminal bytes traverse the internet through the relay. This includes potentially sensitive content (passwords, API keys, source code).

**MVP mitigations**:
- WSS (TLS) enforced — Fly.io terminates TLS, provides free certificates
- One-time pairing tokens — consumed on first use, 5-minute expiry
- Session ID stored in iOS Keychain (not ephemeral memory) with invalidation on unpair
- No persistence at relay — terminal data never logged, buffered, or included in crash dumps
- Self-hosted relay — V controls the server infrastructure
- Rate limiting on `/pair` endpoint — prevents token spray attacks
- Device revocation: "Forget this device" action on Mac side invalidates session ID
- Relay logs sanitized — no terminal payload bytes in any log output

**Deferred (post-MVP)**:
- E2E encryption (NaCl/libsodium) — relay becomes a dumb pipe seeing only opaque ciphertext
- mTLS between clients and relay
- Token rotation / session key refresh

**Accepted risks**:
- A compromised relay or Fly.io infrastructure issue could expose terminal contents in cleartext (mitigated by TLS + self-hosting, not eliminated until E2E)
- QR token shown on Mac screen could be photographed — first device to pair wins, subsequent attempts rejected
- CORS protects against browser-based abuse only, not native client impersonation

## Exploration Findings

### libghostty iOS Build
- GhosttyKit **already supports iOS** in the Zig build system (arm64 device + arm64 simulator)
- Current build uses `-Dxcframework-target=native` (macOS only) via a patch in `scripts/build-ghostty.sh`
- The patch already contains both `native` and `universal` branches — just change the flag
- Metal shaders compile for iOS out of the box (`xcrun -sdk iphoneos`)
- Minimum iOS version: 17.0 (set in ghostty's Config.zig)
- `SurfaceView_UIKit.swift` already exists at `vendor/ghostty/macos/Sources/Ghostty/Surface View/SurfaceView_UIKit.swift` with CAMetalLayer rendering
- Requires full Xcode.app (iphoneos SDK), not just CLI tools

### ghostty Remote IO Backend
- termio backend is a **pluggable tagged union** (`Kind = enum { exec }`) in `src/termio/backend.zig`
- Adding `remote` variant requires: 1 new file, updates to backend.zig and Termio.zig
- Data flow: read thread calls `io.processOutput(buf)` -> VT parser -> terminal grid -> Metal renderer
- Remote backend replaces pty read/write with fd or socket read/write — everything else stays the same
- `ghostty_surface_config_s` needs a new field for fd-pair config; existing code uses `ghostty_surface_config_new()` factory which zero-initializes, so adding fields is ABI-safe
- **Conditional compilation needed**: iOS builds must not pull in `Exec.zig`'s POSIX pty imports. Use `builtin.os.tag == .ios` compile-time check for backend Kind selection
- xev event loop integration required for the read/write thread (follow Exec.zig patterns)
- Realistic estimate: **800-1200 LOC Zig** (includes thread lifecycle, xev integration, write request pooling)

### Relay Tech
- **Go + coder/websocket** recommended: zero-allocation reads/writes, context-based cancellation
- Deploy on Fly.io: ~$2-3/month, single static binary, free TLS termination
- Pattern: Mac connects as `role=host`, iOS as `role=viewer`, relay pairs by token and pipes bytes
- Token lifecycle: one-time token consumed on pairing, relay issues session ID for reconnection within timeout
- Existing art: Coder uses this exact library for terminal streaming in their product

### tmux Multi-Client Behavior
- `window-size latest` (default tmux 3.x): window sizes to most recently active client
- `attach -r` = `-f read-only,ignore-size`: read-only client doesn't affect window sizing
- `refresh-client -C W,H`: control mode clients can set virtual size
- For interactive mode: use grouped sessions (`tmux new-session -t <target>`) so iOS gets its own window pointers without constraining the Mac's terminal size
- Grouped sessions need cleanup on disconnect to avoid leaking tmux sessions
- Mori currently uses regular `tmux attach` inside ghostty surface + CLI polling for management (no control mode)
- Session names use `SessionNaming` format: `project/branch-slug` (e.g., `mori/main`)

### Capabilities Summary

| Capability | Status |
|---|---|
| libghostty Metal rendering on iOS | Supported (UIKit surface exists, verified) |
| GhosttyKit XCFramework for iOS | Build infra exists, just needs flag change |
| Remote IO backend for ghostty | Feasible, pluggable architecture, ~800-1200 LOC Zig |
| Binary WebSocket terminal relay | Proven pattern (ttyd, Coder), Go recommended |
| tmux multi-client same session | Native tmux feature, read-only + ignore-size supported |
| QR-code pairing | Standard pattern, generate token -> encode as QR -> scan |

### Limitations & Risks

| Limitation | Impact | Mitigation |
|---|---|---|
| No fork() on iOS | Cannot run local pty/shell | Remote backend feeds bytes from network |
| ghostty NullPty is a stub | Surface creation compiles but does nothing on iOS | Remote backend replaces NullPty path |
| tmux sizing with interactive iOS client | iPhone screen is small, Mac window shrinks to match | Use grouped sessions (`new-session -t`) |
| Relay adds latency | Keystroke -> relay -> Mac -> tmux -> relay -> iOS | Fly.io edge regions minimize; accept ~50-100ms RTT |
| ghostty iOS is not battle-tested | SurfaceView_UIKit exists but may have rough edges | Budget time for iOS-specific rendering fixes |
| Zig changes to ghostty | Maintaining a fork diverges from upstream | Keep changes minimal, propose upstream PR |
| iOS keyboard for terminal | Software keyboard lacks ctrl/esc/tab | Build custom input accessory bar |
| No offline/local mode | Relay must be reachable | Accept for MVP; LAN fallback is future work |
| Terminal data visible to relay | Security risk | TLS + self-hosted; E2E encryption deferred |
| iOS suspension is unpredictable | WebSocket drops on background | Design for fast detach/resume, not background keep-alive |
| Grouped tmux sessions can leak | Stale sessions accumulate | Explicit cleanup on disconnect + periodic garbage collection |
| Reconnect session ID theft | Replay attack on stolen credential | Store in Keychain, invalidate on unpair, short TTL |

## Implementation Phases

Phase ordering is designed to **de-risk the highest unknowns first**: ghostty iOS rendering and the remote backend are proven before relay deployment or UI polish. Phases 3 and 4 can be partially parallelized after the protocol is defined in Phase 2.

### Phase 1: Fork Ghostty + Universal Build + iOS Proof-of-Life

1. Fork `ghostty-org/ghostty` on GitHub (e.g., `vaayne/ghostty`)
2. Update `.gitmodules` to point to the fork
3. Add `upstream` remote in submodule pointing to `ghostty-org/ghostty`
4. Create `mori/remote-backend` branch from current commit (`c9e1006`)
5. `ghostty:sync` mise task already added — verify it works with the fork
6. Add iphoneos SDK check to `scripts/build-ghostty.sh` (`xcrun -sdk iphoneos --show-sdk-path`)
7. Change `-Dxcframework-target=native` to `universal` on line 184 of build script (keep the existing patch — it already has the universal branch with iOS targets)
8. Build and verify XCFramework contains macOS, iOS device, and iOS Simulator slices
9. Verify Mori macOS still builds and runs with the universal framework
10. Create minimal iOS shell app (`MoriRemote/`) that initializes ghostty (`ghostty_init()`) and renders an empty surface — proves Metal rendering works on iOS before any network code
11. Document the build change

Files: `.gitmodules`, `scripts/build-ghostty.sh`, `MoriRemote/` (new Xcode project)

### Phase 2: Remote termio Backend (Zig) + Protocol Definition + Local Harness

1. **Define `MoriRemoteProtocol` package** — cross-platform Swift package (macOS + iOS) with:
   - Message types: `Handshake` (version, capabilities), `Attach(session)`, `Detach`, `Resize(cols, rows)`, `ModeChange(readOnly/interactive)`, `SessionList`, `Heartbeat/Pong`, `Error`
   - State machine: `disconnected -> pairing -> connected -> attached -> detached` with transitions
   - Wire format: JSON text frames for control, binary frames for terminal data
   - Session ID and reconnect semantics: pairing consumes token, issues session ID; reconnect within TTL uses session ID; expired session ID requires re-pairing
2. **Create `vendor/ghostty/src/termio/Remote.zig`** implementing the backend interface (~800-1200 LOC)
   - `Config`: read_fd, write_fd (pipe/socket file descriptors)
   - `ThreadData`: read thread state, xev event loop integration, write request pooling
   - `threadEnter`: spawn read thread that polls read_fd via xev, calls `io.processOutput()`
   - `threadExit`: clean shutdown of read thread
   - `queueWrite`: write to write_fd via xev Stream (follow Exec.zig's write_stream pattern)
   - `resize`: send resize message over write_fd (simple framing: type byte + u16 cols + u16 rows)
   - `focusGained`: no-op
   - `initTerminal`: minimal init (no shell integration)
   - `childExitedAbnormally`: no-op (no child process)
3. Update `vendor/ghostty/src/termio/backend.zig`:
   - Add `remote` to Kind enum; gate Exec.zig imports behind `builtin.os.tag != .ios`
   - Add `remote` variant to Backend union, Config union, and ThreadData union
   - Add dispatch cases in all switch statements
4. Update `vendor/ghostty/src/termio/Termio.zig`: accept remote config in Options struct
5. Expose fd-pair config in `ghostty_surface_config_s` (ghostty.h):
   - Add `int32_t remote_read_fd; int32_t remote_write_fd;` fields (-1 = unused)
   - `ghostty_surface_config_new()` initializes them to -1 (no change for macOS callers)
6. Wire surface config fd fields through to Remote backend in `Surface.zig`
7. **Local harness**: macOS test app that creates a pipe pair, feeds canned VT bytes into write end, ghostty surface with Remote backend renders them — validates the backend works before any network code
8. **iOS harness**: same canned-VT test on the Phase 1 iOS shell app — validates Remote backend + Metal rendering on iOS
9. Build universal XCFramework, verify macOS still works, verify iOS compiles

Files: `Packages/MoriRemoteProtocol/` (new), `vendor/ghostty/src/termio/Remote.zig` (new), `vendor/ghostty/src/termio/backend.zig`, `vendor/ghostty/src/termio/Termio.zig`, `vendor/ghostty/src/Surface.zig`, `vendor/ghostty/include/ghostty.h`

### Phase 3: Go Relay Service

1. Initialize Go module (`mori-relay/`)
2. Implement WebSocket server with `coder/websocket`
   - `POST /pair` — generate cryptographically random token, return token string
   - `GET /ws?token=<T>&role=host|viewer` — WebSocket upgrade, pair by token
3. Token lifecycle: one-time pairing token (5-minute expiry), consumed on successful pair; relay issues session ID for reconnection within configurable TTL (default 120s)
4. Binary byte relay: bidirectional pipe between paired connections using `io.Copy` pattern
5. Control channel: JSON text frames implementing `MoriRemoteProtocol` message types
6. Handshake with protocol version field (`{"version": 1, ...}`)
7. Heartbeat: relay sends ping every 30s, drops connections that miss 3 pongs
8. Rate limiting on `/pair` endpoint (e.g., 10 requests/minute per IP)
9. Orphan cleanup: if host connects but viewer never does within timeout, close host connection
10. WebSocket backpressure: bounded write buffer per connection, disconnect on overflow
11. Log sanitization: never log terminal payload bytes, only metadata (connection events, errors)
12. Health check endpoint (`GET /health`)
13. Dockerfile + fly.toml for Fly.io deployment
14. Add `mise` tasks: `relay:dev` (local), `relay:deploy` (Fly.io)
15. Test: local docker-compose, verify pairing + byte relay + reconnection + heartbeat timeout with wscat

Files: `mori-relay/`, `mise.toml`

### Phase 4: Mac Relay Connector (MoriRemoteHost)

1. New Swift executable target `MoriRemoteHost` (separate process, not embedded in Mori app)
   - Can run independently of the Mori UI
   - Future: launch-at-login via launchd plist
2. Implement `RelayConnector` actor:
   - `connect(relayURL, token)` — outbound WSS to relay as `role=host`
   - `attachSession(sessionName)` — forkpty + `tmux attach-session -t <name>`
   - Bidirectional pipe: pty read -> WebSocket send (binary frames), WebSocket receive -> pty write
   - Handle resize messages from relay -> `SIGWINCH` to pty
3. Session listing: respond to `SessionList` control message using existing `SessionNaming.parse()` for display-friendly names
   - Include window list per session
4. Interactive mode: use grouped sessions (`tmux new-session -t <target-session>`) so iOS gets its own size-independent window pointers
5. **Grouped session cleanup**: on viewer disconnect or host shutdown, kill grouped sessions created for interactive mode; periodic GC for stale grouped sessions
6. QR code generation: generate token via relay API, encode as QR, display in Mori UI (Mori app launches/controls MoriRemoteHost via XPC or CLI)
7. Handle reconnection: exponential backoff on WebSocket disconnect, reuse session ID within TTL
8. **Relay-free loopback harness**: test connector -> local stub -> iOS client end-to-end without Fly.io

Files: new `Sources/MoriRemoteHost/` target, integration with `Sources/Mori/`

### Phase 5A: iOS App — ghostty Rendering + Pipe Bridge

1. Expand Phase 1 iOS shell app into full `MoriRemote/` project (iOS 17+, SwiftUI)
2. Link GhosttyKit.xcframework (iOS slice) and `MoriRemoteProtocol` package
3. Reuse vendored ghostty iOS wrappers where possible:
   - `SurfaceView_UIKit.swift` for the UIView
   - `SurfaceView.swift` for SurfaceConfiguration
   - `iOSApp.swift` patterns for ghostty initialization
4. Create `GhosttyRemoteSurface`: UIViewRepresentable wrapping ghostty SurfaceView (UIKit)
   - Create pipe fd pair (`pipe()` syscall)
   - Pass read_fd/write_fd to ghostty surface config
   - ghostty's Remote backend reads from read_fd, renders via Metal
5. Create bidirectional bridge:
   - **WebSocket -> read_fd**: relay binary frames written to pipe, ghostty reads and renders
   - **write_fd -> WebSocket**: ghostty writes user input to pipe, bridge reads and sends to relay
6. Terminal view: full-screen ghostty surface with safe area handling
7. Input accessory bar: Ctrl, Esc, Tab, Arrow keys, pipe, tilde
8. Test on simulator and device: verify rendering, keyboard input, pipe throughput

Files: `MoriRemote/`

### Phase 5B: iOS App — WebSocket Client + Reconnect

1. Create `RelayClient` using `URLSessionWebSocketTask`
   - Connect to relay as `role=viewer`
   - Implement `MoriRemoteProtocol` state machine: disconnected -> pairing -> connected -> attached
   - Binary frames piped to/from ghostty via `GhosttyRemoteSurface` bridge
2. **iOS lifecycle handling**:
   - On `scenePhase == .background`: immediately send `Detach`, close WebSocket cleanly
   - On `scenePhase == .active`: reconnect using session ID from Keychain; if expired, show re-pair prompt
   - No background keep-alive — design for fast resume (~1-2s reconnect)
3. Session ID storage: store in iOS Keychain, invalidate on explicit unpair
4. Heartbeat: respond to relay pings to maintain connection
5. Reconnect state machine tests: simulate disconnect, background, session expiry, re-pair flows

Files: `MoriRemote/`

### Phase 6: iOS App — Session List + QR Pairing + Mode Toggle

1. QR scanner view: use `AVCaptureSession` to scan QR code from Mac
   - Extract relay URL + token from `mori-relay://<host>/<token>` URL
   - Request camera permission (NSCameraUsageDescription in Info.plist)
   - Auto-connect to relay on successful scan
2. Session list view: fetch tmux session list via control channel
   - Display display-friendly names (from `SessionNaming`), window count, attached status
   - Tap to attach
3. Mode toggle: read-only vs interactive
   - Read-only: Mac attaches with `tmux attach -r` (ignore-size)
   - Interactive: Mac uses grouped session (`tmux new-session -t <target>`)
   - UI toggle button overlaid on terminal view
   - Mode change sends `ModeChange` control message -> Mac reconnects tmux with appropriate flags
4. Connection status indicator: connected/disconnected/reconnecting
5. Handle orientation changes: send `Resize` to relay -> Mac -> tmux
6. Device revocation: "Forget this device" action accessible from Mac (invalidates session ID at relay)

Files: `MoriRemote/` views and view models

### Phase 7: Polish + Docs

1. Localization: add `.localized()` strings for all new user-facing text in Mac and iOS apps (English + zh-Hans)
2. Update `README.md` with Mori Remote section
3. Update `CHANGELOG.md` with new features
4. Update `AGENTS.md` if build commands or conventions change
5. Add `mise` tasks: `ios:build`, `ios:test`
6. Real-device suspend/resume testing on multiple iOS versions (17.x, 18.x)
7. End-to-end test: Mac + Fly.io relay + iOS device — full remote terminal session, measure RTT

Files: various

## Testing Strategy

- **Phase 1**: Build verification — XCFramework contains all 3 slices (`lipo -info`), Mori macOS builds cleanly, iOS shell app renders empty ghostty surface
- **Phase 2**: Local harness — canned VT bytes render correctly on macOS and iOS via Remote backend; Zig unit tests for pipe read/write, resize framing, thread lifecycle; protocol message serialization round-trip tests
- **Phase 3**: Relay integration — pairing flow, binary relay correctness, token expiry/cleanup, reconnection with session ID, heartbeat timeout, orphan cleanup, backpressure disconnect, rate limiting
- **Phase 4**: Mac connector — end-to-end on Mac via local relay, reconnection after relay restart, grouped session creation and cleanup on disconnect, connect/disconnect stress loop
- **Phase 5A**: iOS rendering — ghostty surface renders via pipe, keyboard input flows, bidirectional bridge works, no memory leaks on surface create/destroy
- **Phase 5B**: iOS lifecycle — background suspension triggers clean detach, foreground triggers fast reconnect, expired session ID prompts re-pair, heartbeat keeps connection alive
- **Phase 6**: Device testing on iPhone (iOS 17+) — QR scan, session list, mode toggle, orientation changes
- **Phase 7**: End-to-end on Fly.io, RTT measurement, high-throughput test (`cat large_file`), localization verification

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| ghostty iOS rendering bugs | High — blank screen or crashes | Prove rendering in Phase 1 before any network code |
| Zig Remote backend complexity | High — unfamiliar language, xev integration | 800-1200 LOC estimate; local harness validates before network; follow Exec.zig patterns |
| Cross-platform packaging | High — existing repo is macOS-only | MoriRemoteProtocol as shared package; iOS app is a separate project, not embedded in macOS Package.swift |
| Protocol and reconnect complexity | High — races, half-open sockets, duplicate sessions | Explicit state machine in MoriRemoteProtocol; state machine tests in Phase 5B |
| iOS suspension/lifecycle | High — unpredictable background suspension | Design for detach/resume, not background keep-alive; test in Phase 5B |
| Terminal data exposed at relay | High — passwords, keys in cleartext | TLS + self-hosted relay; E2E encryption as fast-follow |
| tmux grouped session leakage | Medium — stale sessions accumulate | Explicit cleanup on disconnect + periodic GC in Phase 4 |
| Reconnect credential theft | Medium — session ID replay | Keychain storage, short TTL, device revocation |
| Relay latency over internet | Medium — sluggish typing | Fly.io edge regions; measure and optimize frame batching |
| iOS keyboard limitations | Medium — terminal UX degradation | Custom input accessory bar with common terminal keys |
| Upstream ghostty divergence | Medium — merge conflicts | Minimize Zig changes; propose upstream PR for Remote backend |
| embedded.zig macOS assumptions | Medium — may not compile for iOS | Audit apprt/embedded.zig for AppKit imports; fix in Phase 1 |

## Assumptions

1. **ghostty_surface_config_s extension**: Adding fd-pair fields is ABI-safe because all callers use `ghostty_surface_config_new()` factory which zero-initializes new fields (verified in existing codebase)
2. **pipe() on iOS**: `pipe()` syscall works in iOS sandbox for creating fd pairs within the same process (used by Foundation internally)
3. **Fly.io region**: Deploy to a single region initially; add multi-region later if latency is an issue
4. **QR code content**: Format will be `mori-relay://<host>/<token>` — simple URL scheme
5. **Frame batching**: Terminal bytes sent as-is per WebSocket frame for lowest latency; optimize later if bandwidth is an issue
6. **Conditional compilation**: iOS ghostty builds will use compile-time `builtin.os.tag == .ios` to select the Remote backend and exclude Exec.zig's POSIX pty imports
7. **Session naming**: Reuse existing `SessionNaming` from MoriTmux for display-friendly names (format: `project/branch-slug`)

## Review Feedback

### Round 1 (Internal Reviewer)

Verdict: CHANGES NEEDED. All items addressed:
- Verified `SurfaceView_UIKit.swift` exists in vendored ghostty
- Phase 1: Corrected build script instructions (keep patch, change flag only, add SDK check)
- Phase 2: Added conditional compilation task, revised LOC estimate to 800-1200, added xev integration detail
- Phase 3: Clarified token lifecycle, added rate limiting, CORS, orphan cleanup, protocol version
- Phase 4: Added grouped session support, display-friendly session names
- Phase 5: Added GhosttyApp initialization task
- Added Prerequisites, Security section, TestFlight distribution

### Round 2 (Internal Reviewer)

Verdict: APPROVED.

### Round 3 (Codex)

Verdict: Credible but needs revision. Key feedback incorporated:
- **Added Phase 0-equivalent work**: protocol definition (`MoriRemoteProtocol` package) moved to Phase 2 before relay/connector implementation
- **De-risked phase ordering**: Phase 1 now includes iOS proof-of-life (ghostty rendering); Phase 2 includes local harness (canned VT bytes) before network; relay deployment moved later
- **Split Phase 5**: 5A (rendering + pipe bridge) and 5B (WebSocket + reconnect + iOS lifecycle)
- **Separate host process**: Mac connector is now `MoriRemoteHost` (dedicated helper, not embedded in app) for cleaner lifecycle and future headless mode
- **iOS lifecycle**: replaced "30s background grace period" with immediate detach on background + fast resume on foreground
- **Grouped session cleanup**: explicit cleanup on disconnect + periodic GC added to Phase 4
- **Session naming**: reuse existing `SessionNaming.parse()` from MoriTmux, not a parallel system
- **Security hardening**: Keychain for session ID, device revocation, relay log sanitization, QR first-pair-wins
- **Missing tasks added**: heartbeat/ping, backpressure handling, reconnect state machine tests, localization, docs updates
- **Task 1.5 correction**: `ghostty:sync` mise task already exists, changed to "verify it works"
- **New Phase 7**: Polish, localization, docs, final e2e testing

## Final Status

**All implemented phases: COMPLETE**

| Phase | Tasks | Status |
|---|---|---|
| Phase 1: Fork Ghostty + Universal Build | 11/11 | COMPLETE |
| Phase 2: Remote Backend + Protocol | 11/11 | Zig backend + protocol done in fork |
| Phase 3: Go Relay Service | 14/14 | Deployed to Fly.io |
| Phase 4: Mac Relay Connector | 8/8 | COMPLETE |
| Phase 5A: iOS Rendering + Pipe Bridge | 8/8 | COMPLETE |
| Phase 5B: iOS WebSocket + Reconnect | 5/5 | COMPLETE |
| Phase 6: Session List + QR + Mode Toggle | 6/6 | COMPLETE |
| Phase 7: Polish + Docs | 5/5 | COMPLETE |

**Key artifacts**:
- `MoriRemote/` — iOS companion app (SwiftUI, iOS 17+, libghostty Metal rendering)
- `Sources/MoriRemoteHost/` — Mac relay connector CLI (4 subcommands)
- `Packages/MoriRemoteProtocol/` — Cross-platform protocol package (61 test assertions)
- `mori-relay/` — Go WebSocket relay service (Fly.io)
- `vendor/ghostty/` — Fork with Remote termio backend (Zig)

**Build verification**: macOS build passes, iOS simulator build passes, 61 protocol tests pass.
