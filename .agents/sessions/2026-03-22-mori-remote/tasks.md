# Tasks: Mori Remote

## Phase 1: Fork Ghostty + Universal Build + iOS Proof-of-Life

- [ ] 1.1 Fork `ghostty-org/ghostty` on GitHub
- [ ] 1.2 Update `.gitmodules` to point to fork
- [ ] 1.3 Add `upstream` remote in submodule pointing to `ghostty-org/ghostty`
- [ ] 1.4 Create `mori/remote-backend` branch from current commit (`c9e1006`)
- [ ] 1.5 Verify `ghostty:sync` mise task works with the fork (already added)
- [ ] 1.6 Add iphoneos SDK check to `scripts/build-ghostty.sh`
- [ ] 1.7 Change `-Dxcframework-target=native` to `universal` (line 184, keep existing patch)
- [ ] 1.8 Build and verify XCFramework contains macOS, iOS device, and iOS Simulator slices
- [ ] 1.9 Verify Mori macOS still builds and runs with universal framework
- [ ] 1.10 Create minimal iOS shell app (`MoriRemote/`) with ghostty_init() + empty surface render
- [ ] 1.11 Document the build change

## Phase 2: Remote termio Backend (Zig) + Protocol + Local Harness

- [ ] 2.1 Define `MoriRemoteProtocol` Swift package (message types, state machine, wire format)
- [ ] 2.2 Create `vendor/ghostty/src/termio/Remote.zig` with full backend interface
- [ ] 2.3 Update `backend.zig`: add `remote` to Kind enum and all unions/switches
- [ ] 2.4 Handle conditional compilation: gate Exec.zig POSIX imports behind `builtin.os.tag != .ios`
- [ ] 2.5 Update `Termio.zig`: accept remote config in Options
- [ ] 2.6 Add `remote_read_fd`/`remote_write_fd` fields to `ghostty_surface_config_s` in ghostty.h
- [ ] 2.7 Wire surface config fd fields through `Surface.zig` to Remote backend
- [ ] 2.8 macOS local harness: canned VT bytes -> pipe -> Remote backend -> ghostty render
- [ ] 2.9 iOS local harness: same canned VT test on MoriRemote shell app
- [ ] 2.10 Build universal XCFramework, verify macOS still works, verify iOS compiles
- [ ] 2.11 Protocol message serialization round-trip tests

## Phase 3: Go Relay Service

- [ ] 3.1 Initialize Go module (`mori-relay/`)
- [ ] 3.2 Implement WebSocket server (`POST /pair`, `GET /ws`)
- [ ] 3.3 Token lifecycle: one-time pairing -> session ID for reconnection (configurable TTL)
- [ ] 3.4 Binary byte relay: bidirectional pipe between paired connections
- [ ] 3.5 Control channel: JSON text frames implementing MoriRemoteProtocol messages
- [ ] 3.6 Protocol version in handshake
- [ ] 3.7 Heartbeat: ping every 30s, drop on 3 missed pongs
- [ ] 3.8 Rate limiting on `/pair`, log sanitization (no terminal bytes in logs)
- [ ] 3.9 Orphan cleanup: timeout for unpaired host connections
- [ ] 3.10 WebSocket backpressure: bounded write buffer, disconnect on overflow
- [ ] 3.11 Health check endpoint
- [ ] 3.12 Dockerfile + fly.toml
- [ ] 3.13 Add mise tasks: `relay:dev`, `relay:deploy`
- [ ] 3.14 Test: pairing, relay, reconnection, heartbeat timeout, backpressure

## Phase 4: Mac Relay Connector (MoriRemoteHost)

- [ ] 4.1 New Swift executable target `MoriRemoteHost` (separate process)
- [ ] 4.2 Implement `RelayConnector` actor (WSS connect, forkpty, bidirectional pipe)
- [ ] 4.3 Session listing using `SessionNaming.parse()` for display-friendly names
- [ ] 4.4 Grouped session support for interactive mode (`new-session -t`)
- [ ] 4.5 Grouped session cleanup on viewer disconnect + periodic GC
- [ ] 4.6 QR code generation and display (Mori app launches/controls MoriRemoteHost)
- [ ] 4.7 Reconnection with exponential backoff + session ID reuse
- [ ] 4.8 Relay-free loopback harness: connector -> local stub -> iOS client e2e

## Phase 5A: iOS App — ghostty Rendering + Pipe Bridge

- [ ] 5A.1 Expand MoriRemote into full project (iOS 17+, SwiftUI)
- [ ] 5A.2 Link GhosttyKit.xcframework + MoriRemoteProtocol
- [ ] 5A.3 Reuse vendored ghostty iOS wrappers (SurfaceView_UIKit, SurfaceConfiguration)
- [ ] 5A.4 Create `GhosttyRemoteSurface` (UIViewRepresentable, pipe fd pair)
- [ ] 5A.5 Bidirectional bridge: WebSocket -> read_fd AND write_fd -> WebSocket
- [ ] 5A.6 Terminal view with safe area handling
- [ ] 5A.7 Input accessory bar (Ctrl, Esc, Tab, arrows)
- [ ] 5A.8 Test on simulator and device

## Phase 5B: iOS App — WebSocket Client + Reconnect

- [ ] 5B.1 Create `RelayClient` (URLSessionWebSocketTask, MoriRemoteProtocol state machine)
- [ ] 5B.2 iOS lifecycle: detach on background, reconnect on foreground (no background keep-alive)
- [ ] 5B.3 Session ID storage in iOS Keychain with invalidation
- [ ] 5B.4 Heartbeat response to relay pings
- [ ] 5B.5 Reconnect state machine tests (disconnect, background, session expiry, re-pair)

## Phase 6: iOS App — Session List + QR Pairing + Mode Toggle

- [ ] 6.1 QR scanner view (AVCaptureSession, camera permission)
- [ ] 6.2 Session list view (control channel, SessionNaming display names, tap to attach)
- [ ] 6.3 Mode toggle (read-only vs interactive)
- [ ] 6.4 Connection status indicator
- [ ] 6.5 Orientation change -> Resize message
- [ ] 6.6 Device revocation: "Forget this device" from Mac side

## Phase 7: Polish + Docs

- [ ] 7.1 Localization: `.localized()` strings for Mac + iOS (English + zh-Hans)
- [ ] 7.2 Update README.md, CHANGELOG.md, AGENTS.md
- [ ] 7.3 Add mise tasks: `ios:build`, `ios:test`
- [ ] 7.4 Real-device suspend/resume testing (iOS 17.x, 18.x)
- [ ] 7.5 End-to-end test: Mac + Fly.io + iOS device, RTT measurement
