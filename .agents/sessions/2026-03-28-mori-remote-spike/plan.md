# Plan: Mori Remote iOS — Phase 0 Spike

## Overview

Prove that an iOS app can connect to a remote host via SSH, attach to a tmux session
in control mode (`tmux -C`), parse control-mode output, render one pane in libghostty,
and send keyboard input back via `send-keys`. This is the Phase 0 spike from `remote.md`.

### Goals

- Validate the end-to-end data path: SSH → tmux control mode → libghostty render → send-keys input
- Make existing packages (`MoriCore`, `MoriTmux`) cross-platform (macOS 14+ / iOS 17+)
- Build GhosttyKit.xcframework with iOS support (universal: macOS + iOS + iOS Simulator)
- Create a new `MoriSSH` package with SwiftNIO SSH transport
- Create a tmux control-mode parser in `MoriTmux`
- Ship a minimal iOS app target that proves the spike

### Success Criteria

- [ ] SSH connection established from iOS app to remote host (password auth; key auth stretch goal)
- [ ] `tmux -C new-session` or `attach-session` succeeds over SSH exec channel
- [ ] `%output` bytes from one pane are parsed and fed into libghostty
- [ ] Terminal renders correctly on iPhone via libghostty with pipe backend (simulator or device)
- [ ] Renderer size communicated to tmux via `refresh-client -C <cols>,<rows>` on attach and resize
- [ ] Keyboard input via `send-keys` reaches the remote pane
- [ ] Existing macOS app builds and all tests pass without regressions

**Hard gate:** libghostty must render on iOS. If the pipe backend doesn't work, the spike is marked **partial/blocked**, not successful. A `UITextView` fallback is acceptable only for transport/parser debugging, not for meeting success criteria.

### Out of Scope

- Full session/window/pane management UI (Phase 1+)
- Flow control (`pause-after`, `%pause`/`%continue`) (Phase 3)
- iPad multi-column layout (Phase 4)
- Reconnect/resume logic (Phase 3)
- Theming sync with macOS app (Phase 4)
- Mouse passthrough (Phase 4)
- Agent forwarding, jump hosts, ProxyCommand
- App Store distribution, signing, provisioning
- SSH host key verification (spike uses accept-all; TOFU for production)
- Auto-reconnect on network changes or SSH disconnect
- Public key auth from iOS sandbox (no filesystem access to `~/.ssh/`; stretch goal with bundled/imported keys)

## Technical Approach

The spike wires six layers together in the minimal viable way:

```
┌─────────────────────────────────────────┐
│  iOS App (SwiftUI)                      │
│  ┌─────────────┐  ┌──────────────────┐  │
│  │ Connect Form│  │ Terminal View     │  │
│  │ (host/auth) │  │ (GhosttyBridge)  │  │
│  └──────┬──────┘  └────────▲─────────┘  │
│         │                  │ bytes       │
│  ┌──────▼──────────────────┴─────────┐  │
│  │ SpikeCoordinator                  │  │
│  │ wires SSH → ControlClient → View  │  │
│  └──────┬──────────────────┬─────────┘  │
│         │                  │ send-keys   │
│  ┌──────▼──────┐  ┌───────▼──────────┐  │
│  │ SSHConnection│  │TmuxControlClient │  │
│  │ Manager     │  │(control-mode     │  │
│  │ (SwiftNIO)  │  │ parser + line    │  │
│  └─────────────┘  │ buffer)          │  │
│                   └──────────────────┘  │
└─────────────────────────────────────────┘
          │ SSH channel
          ▼
    Remote tmux server
```

### Key Design Decisions

1. **SwiftNIO SSH** (`swift-nio-ssh` 0.8.0+) for transport — programmatic SSH, no shelling out to `/usr/bin/ssh` (unavailable on iOS). Pinned version for API stability.
2. **Use `tmux -C` (single-C), not `tmux -CC`** — `-CC` emits DCS framing (`ESC P1000p` prologue, `ESC \` on exit) that complicates the newline-based line buffer. `-C` (single) gives the same control-mode protocol without DCS wrapping, which is correct for a programmatic client on a non-terminal SSH exec channel.
3. **Byte-oriented control-mode parser** — `%output` payloads escape non-printable characters and backslash using octal `\ooo` sequences (e.g., `\012` = newline, `\134` = backslash). All other bytes (including high-bit/raw bytes > 0x7E) are preserved verbatim. The parser scans for `\` followed by exactly 3 octal digits → convert to byte. `\134` → `\` byte. Any other `\` sequence is treated as literal (defensive). Parser stays `Data`-based, not `String`-based, until after unescaping.
4. **Line buffering in `TmuxControlClient`** — SSH channels deliver arbitrary-sized `Data` chunks. `TmuxControlClient` maintains an internal `Data` buffer. Incoming chunks are appended; complete `\n`-terminated lines are extracted and parsed. Partial lines remain buffered. Must handle: one line split across multiple chunks, multiple lines in one chunk.
5. **Command correlation by server-assigned command number** — `TmuxControlClient` serializes commands one at a time for the spike (no concurrent in-flight commands). On `sendCommand`, it writes the command (newline-terminated), then waits for a `%begin <ts> <cmdnum> <flags>` response. It records the server-provided `commandNumber` from `%begin`, accumulates response lines (non-`%`-prefixed lines within the block), then matches `%end <ts> <cmdnum> <flags>` / `%error <ts> <cmdnum> <flags>` against that recorded number. Uses `CheckedContinuation<String, Error>` for the await. `%error` rejects the continuation with the accumulated error lines.
6. **Pipe backend for libghostty** — no PTY on iOS; bytes fed directly into ghostty surface via C API.
7. **`send-keys` for input** — regular text uses `send-keys -l -t %<pane> '<escaped>'` with single-quote escaping (`'` → `'\''`). Special keys use tmux key names: `send-keys -t %<pane> Enter`, `send-keys -t %<pane> C-c`, `send-keys -t %<pane> Up`, etc.
8. **Renderer size → tmux** — after attach and on every renderer resize, send `refresh-client -C <cols>,<rows>` so the remote tmux client size tracks the iPhone screen. Compute cols/rows from the ghostty surface grid dimensions.
9. **Minimal coordinator pattern** — `SpikeCoordinator` wires everything; no MVVM/architecture overhead for the spike.
10. **SSH host key verification: accept-all** — spike-only. Production will use TOFU (trust on first use) with stored fingerprints.
11. **Disconnect handling** — on SSH disconnect or tmux `%exit` notification, `SpikeCoordinator` transitions to `.disconnected(error:)` state and displays the error. No auto-reconnect for the spike.
12. **Xcode project for iOS app** — needed for iOS provisioning, signing, and `Info.plist`. SPM packages shared via local path dependencies. (Pure SPM executable targets can't handle iOS app lifecycle requirements like entitlements and asset catalogs.)
13. **Password auth primary, key auth stretch goal** — iOS sandbox has no access to `~/.ssh/`. Password auth is the primary spike path. Key auth is a stretch goal: import key data from iOS file picker or paste, store in app sandbox, pass `Data` directly to SwiftNIO SSH. Not required for spike success.

### Components

- **MoriCore** (refactored): Add `.iOS(.v17)` platform. Pure models, no macOS-specific code.
- **MoriTmux** (refactored + extended): Add `.iOS(.v17)` platform. Gate `TmuxCommandRunner`/`TmuxBackend` behind `#if os(macOS)`. Add new `TmuxControlParser` and `TmuxControlClient` (cross-platform).
- **MoriSSH** (new package): SwiftNIO SSH-based `SSHConnectionManager` actor. Password + public key auth. Channel multiplexing. `swift-nio-ssh` 0.8.0+.
- **MoriTerminal** (refactored): Build universal GhosttyKit.xcframework. Add iOS 17+ platform. Gate macOS code behind `#if os(macOS)`. Add `GhosttyPipeRenderer` (iOS: UIView + pipe backend + CADisplayLink).
- **MoriRemote** (new iOS app target): Xcode project importing shared packages. Minimal SwiftUI: connect form → terminal view.

## Implementation Phases

### Phase 1: Cross-Platform Package Foundation

Make `MoriCore` and `MoriTmux` compile for both macOS 14+ and iOS 17+.

1. Update `MoriCore/Package.swift` to add `.iOS(.v17)` platform (files: `Packages/MoriCore/Package.swift`)
2. Audit `MoriCore` sources for macOS-only APIs. `SSHCommandSupport.swift` uses `CryptoKit` (cross-platform), `Darwin` (cross-platform), `Foundation.Process`-free — should be clean. `NotificationDebouncer` uses `DispatchQueue` — cross-platform. (files: `Packages/MoriCore/Sources/MoriCore/**/*.swift`)
3. Update `MoriTmux/Package.swift` to add `.iOS(.v17)` platform (files: `Packages/MoriTmux/Package.swift`)
4. Gate macOS-only code in `TmuxCommandRunner.swift` behind `#if os(macOS)` — the entire file uses `Foundation.Process`, `FileManager.isExecutableFile`, etc. (files: `Packages/MoriTmux/Sources/MoriTmux/TmuxCommandRunner.swift`)
5. Gate `TmuxBackend.swift` behind `#if os(macOS)` — it depends on `TmuxCommandRunner` (files: `Packages/MoriTmux/Sources/MoriTmux/TmuxBackend.swift`)
6. Gate `PaneStateDetector.swift` and `AgentDetector.swift` behind `#if os(macOS)` if they depend on macOS-only types (files: `Packages/MoriTmux/Sources/MoriTmux/PaneStateDetector.swift`, `AgentDetector.swift`)
7. Audit and gate test targets: add `#if os(macOS)` guards around tests that exercise macOS-only types (`TmuxBackend`, `TmuxCommandRunner`). Ensure shared types (`TmuxParser`, `TmuxSession`, `TmuxWindow`, `TmuxPane`) remain testable on both platforms. (files: `Packages/MoriTmux/Tests/MoriTmuxTests/`)
8. Verify macOS app still builds (`mise run build`) and existing tests pass (`mise run test:core`, `mise run test:tmux`)

### Phase 2: MoriSSH Package — SSH Transport

Create a new `Packages/MoriSSH` package providing SwiftNIO SSH-based connectivity.

1. Create `Packages/MoriSSH/Package.swift` with dependencies: `swift-nio-ssh` from `0.8.0`, `swift-nio` from `2.65.0`. Platforms: macOS 14+ / iOS 17+. (files: `Packages/MoriSSH/Package.swift`)
2. Create `SSHAuthConfig.swift` — auth configuration types: `.password(String)`, `.publicKey(keyData: Data, passphrase: String?)`. Key data is raw PEM/OpenSSH bytes (not a file path — iOS sandbox has no `~/.ssh/`). For the spike, password auth is primary; key auth is a stretch goal. (files: `Packages/MoriSSH/Sources/MoriSSH/SSHAuthConfig.swift`)
3. Create `SSHConnectionManager.swift` — actor managing one SSH connection per host. Handles TCP connect (NIO `ClientBootstrap`) → SSH handshake → auth → channel creation. Host key verification: accept-all for spike (`// TODO: TOFU for production`). Provides `openExecChannel(command:) async throws -> SSHChannel` returning bidirectional byte stream. Uses NIO `EventLoopGroup` shared across channels. (files: `Packages/MoriSSH/Sources/MoriSSH/SSHConnectionManager.swift`)
4. Create `SSHChannel.swift` — wrapper around NIO SSH child channel. Exposes `var inbound: AsyncThrowingStream<Data, Error>` (reads from channel) and `func write(_ data: Data) async throws` (writes to channel). Handles SSH channel EOF and close. (files: `Packages/MoriSSH/Sources/MoriSSH/SSHChannel.swift`)
5. Create `SSHError.swift` — error types: `connectionFailed(String)`, `authenticationFailed`, `timeout`, `channelError(String)`, `disconnected` (files: `Packages/MoriSSH/Sources/MoriSSH/SSHError.swift`)
6. Create executable test target `MoriSSHTests` with unit tests: auth config construction, error type coverage, mock transport protocol conformance. (files: `Packages/MoriSSH/Tests/MoriSSHTests/SSHTests.swift`)

### Phase 3: Tmux Control-Mode Client

Add control-mode protocol parsing to `MoriTmux` (cross-platform, no macOS-only deps).

1. Create `TmuxControlLine.swift` — enum for parsed control-mode line types:
   - `.output(paneId: String, data: Data)` — pane output with decoded bytes
   - `.begin(timestamp: Int, commandNumber: Int, flags: Int)` — command response start
   - `.end(timestamp: Int, commandNumber: Int, flags: Int)` — command response end (tmux sends 3 fields)
   - `.error(timestamp: Int, commandNumber: Int, flags: Int)` — command error (tmux sends 3 fields)
   - `.notification(TmuxNotification)` — async notification
   - `.plainLine(String)` — non-`%` line (response text within a block; block tracking is client's job)
   (files: `Packages/MoriTmux/Sources/MoriTmux/TmuxControlLine.swift`)

2. Create `TmuxNotification.swift` — enum for async notifications:
   - `sessionsChanged`, `sessionChanged(sessionId: String, name: String)`
   - `windowAdd(windowId: String)`, `windowClose(windowId: String)`
   - `windowRenamed(windowId: String, name: String)`
   - `windowPaneChanged(windowId: String, paneId: String)`
   - `layoutChanged(windowId: String, layout: String)`
   - `exit(reason: String?)`
   - `unknown(String)` — for forward compatibility
   (files: `Packages/MoriTmux/Sources/MoriTmux/TmuxNotification.swift`)

3. Create `TmuxControlParser.swift` — stateless line parser, one line → one `TmuxControlLine`.
   **`%output` protocol**: `%output %<pane-id> <data>\n` where `<data>` escapes non-printable characters and backslash as octal `\ooo` (3 digits). `\012` = newline, `\134` = backslash. High-bit bytes (> 0x7E) are preserved verbatim (tmux may pass raw non-UTF-8). The trailing `\n` is the line terminator, not part of the payload.
   **Parsing rules**: Line starting with `%` → control line. Lines not starting with `%` → `.plainLine(String)` (response text within a `%begin/%end` block; block-tracking is the client's job, not the parser's). Octal unescape function: scan for `\` followed by exactly 3 octal digits → convert to byte value. Any other `\` is preserved as-is (defensive).
   **Note**: The parser is stateless. It does NOT track whether we are inside a `%begin/%end` block — that's `TmuxControlClient`'s responsibility.
   (files: `Packages/MoriTmux/Sources/MoriTmux/TmuxControlParser.swift`)

4. Create `TmuxTransport.swift` — protocol abstracting the byte channel so `TmuxControlClient` is testable without real SSH:
   ```swift
   public protocol TmuxTransport: Sendable {
       var inbound: AsyncThrowingStream<Data, Error> { get }
       func write(_ data: Data) async throws
       func close() async
   }
   ```
   (files: `Packages/MoriTmux/Sources/MoriTmux/TmuxTransport.swift`)

5. Create `TmuxControlClient.swift` — actor that owns a `TmuxTransport`.
   **Line buffering**: maintains a `Data` buffer. Incoming chunks are appended; complete `\n`-terminated lines are extracted and fed to `TmuxControlParser`. Partial lines remain buffered. Must handle: one line split across multiple SSH data chunks, multiple lines in one chunk.
   **Block tracking**: the client (not the parser) tracks whether we are inside a `%begin/%end` block. When inside a block, `.plainLine` results are accumulated as response lines.
   **Command serialization**: for the spike, commands are sent one at a time (no concurrent in-flight). On `sendCommand`, writes the command (newline-terminated) and waits. Records the server-provided `commandNumber` from the `%begin` response. Accumulates `.plainLine` responses. On `%end` with matching `commandNumber`, resolves `CheckedContinuation<String, Error>` with joined lines. On `%error`, rejects the continuation with accumulated error text. On transport EOF/close, cancels any pending command continuation with `SSHError.disconnected`.
   **Public API**:
   - `func sendCommand(_ command: String) async throws -> String` — sends command, awaits `%begin/%end` response
   - `var paneOutput: AsyncStream<(paneId: String, data: Data)>` — stream of decoded pane output
   - `var notifications: AsyncStream<TmuxNotification>` — stream of async notifications
   - `func start() async` — begins reading from transport
   - `func stop() async` — closes transport and cancels in-flight commands with error
   (files: `Packages/MoriTmux/Sources/MoriTmux/TmuxControlClient.swift`)

6. Add control-mode parser + client tests to `MoriTmuxTests`:
   **Parser tests:**
   - Parse `%output %0 hello\012world` → paneId `%0`, data with `\n` between hello/world
   - Parse `%output %5 test\134backslash` → data with literal backslash
   - Parse `%output %2 high\302\251bit` → raw high-bit bytes preserved (©)
   - Parse `%begin 1711000000 1 0` / `%end 1711000000 1 0` command block
   - Parse notifications: `%sessions-changed`, `%window-add @1`, `%exit`
   - Non-`%` line → `.plainLine(...)`
   - Malformed lines: missing fields, unknown `%` prefixes → graceful handling
   **Client tests (mock transport):**
   - Send command → receive correlated `%begin/%end` response with accumulated lines
   - `%error` → continuation rejected with error text
   - One control line split across multiple data chunks → correctly buffered and parsed
   - Multiple control lines in one data chunk → all parsed
   - Transport EOF during pending command → continuation cancelled with disconnect error
   - `%output` routed to `paneOutput` stream
   (files: `Packages/MoriTmux/Tests/MoriTmuxTests/TmuxControlParserTests.swift`)

### Phase 4: GhosttyKit iOS Build + Terminal Bridge

Build GhosttyKit.xcframework with iOS support and create an iOS-compatible terminal renderer.

1. Update `scripts/build-ghostty.sh` to accept `--universal` flag that builds with `-Dxcframework-target=universal` (macOS + iOS + iOS Simulator). Keep current behavior as `--native` (default). When `--universal` is passed, skip the native-only patch so the original `GhosttyXCFramework.zig` builds all three slices. Document that `--universal` requires Xcode.app with iOS SDK. (files: `scripts/build-ghostty.sh`)

2. Build and validate: run `bash scripts/build-ghostty.sh --clean --universal`. Verify the xcframework at `Frameworks/GhosttyKit.xcframework` contains:
   - `macos-arm64_x86_64/` (universal macOS)
   - `ios-arm64/` (device)
   - `ios-arm64-simulator/` (simulator)
   If this fails (Zig/SDK issues), fall back to building iOS slice separately. This is the **hard gate** — if the universal build doesn't work and no iOS slice can be produced, the spike is blocked. Assess before continuing.

3. Update `MoriTerminal/Package.swift` to add `.iOS(.v17)` platform. Remove the `Carbon` linker setting behind `#if os(macOS)` or move it conditional. (files: `Packages/MoriTerminal/Package.swift`)

4. Gate all macOS-specific files behind `#if os(macOS)`: `GhosttyApp.swift`, `GhosttyAdapter.swift`, `GhosttySurfaceView.swift`, `GhosttyConfigFile.swift`, `GhosttyConfigWriter.swift`, `GhosttyThemeInfo.swift`, `NativeTerminalAdapter.swift`, `TerminalSurfaceCache.swift`, `TerminalHost.swift`, `ANSIParser.swift`. Wrap entire file contents (after imports) in `#if os(macOS) ... #endif`. (files: all files in `Packages/MoriTerminal/Sources/MoriTerminal/`)

5. Create `GhosttyiOSApp.swift` — iOS equivalent of `GhosttyApp.swift` singleton, gated behind `#if os(iOS)`:
   - Manages the `ghostty_app_t` lifecycle
   - `start()`: calls `ghostty_init`, creates config (minimal, no user config file loading), creates app
   - Uses `CADisplayLink` for `ghostty_app_tick` calls
   - Simplified runtime config: no clipboard callbacks, no action handler for the spike
   - Provides `createSurface(config:) -> ghostty_surface_t?`
   (files: `Packages/MoriTerminal/Sources/MoriTerminal/GhosttyiOSApp.swift`)

6. Create `GhosttyPipeRenderer.swift` — iOS terminal renderer, gated behind `#if os(iOS)`:
   - `UIView` subclass with Metal layer (`CAMetalLayer`)
   - Owns one `ghostty_surface_t` created with pipe backend
   - `func feedBytes(_ data: Data)` — writes bytes to ghostty surface via the pipe backend's write API
   - On `layoutSubviews`: calls `ghostty_surface_set_size` with pixel dimensions × scale factor
   - `CADisplayLink` drives `ghostty_surface_draw` (or relies on `GhosttyiOSApp` tick)
   - Minimal: no input handling (handled by coordinator), no clipboard, no IME
   (files: `Packages/MoriTerminal/Sources/MoriTerminal/GhosttyPipeRenderer.swift`)

### Phase 5: iOS App Target + End-to-End Wiring

Create the iOS app and wire all layers together.

1. Create `MoriRemote/` Xcode project structure:
   - `MoriRemote.xcodeproj` (iOS app target, deployment target iOS 17.0)
   - `MoriRemote/MoriRemoteApp.swift` (app entry point)
   - `MoriRemote/Info.plist`
   - `MoriRemote/Assets.xcassets`
   - Add SPM local package dependencies: `../Packages/MoriCore`, `../Packages/MoriTmux`, `../Packages/MoriSSH`, `../Packages/MoriTerminal`
   - Link `MoriCore`, `MoriTmux`, `MoriSSH`, `MoriTerminal` frameworks
   (files: `MoriRemote/` directory)

2. Create `ConnectView.swift` — SwiftUI form: host, port (default 22), username, password field. "Connect" button. Binds to `SpikeCoordinator` state. Shows errors from `.disconnected` state. (Password auth only for spike; key auth is stretch goal.) (files: `MoriRemote/MoriRemote/ConnectView.swift`)

3. Create `TerminalView.swift` — SwiftUI wrapper using `UIViewRepresentable` around `GhosttyPipeRenderer`. Displays the terminal surface. Sizes to fill available space. (files: `MoriRemote/MoriRemote/TerminalView.swift`)

4. Create `SpikeCoordinator.swift` — `@MainActor @Observable` class that orchestrates the spike flow:
   - **State**: `enum SpikeState { case disconnected(Error?), connecting, connected, attached(paneId: String) }`
   - `connect(host:port:user:auth:)` → creates `SSHConnectionManager`, connects, transitions to `.connected`
   - `attachSession(name:)` → opens exec channel with `tmux -C new-session -A -s <name>` (single `-C`, no DCS framing), wraps in `SSHChannelTransport`, creates `TmuxControlClient`, starts it, sends `list-panes -F '#{pane_id}'` to get first pane ID, sends `refresh-client -C <cols>,<rows>` with initial renderer size, transitions to `.attached`
   - Subscribes to `paneOutput` stream in a `Task`, feeds bytes to `GhosttyPipeRenderer`
   - On renderer resize: sends `refresh-client -C <cols>,<rows>` to tmux so remote session tracks iPhone screen size
   - Subscribes to `notifications` stream, handles `%exit` → transition to `.disconnected`
   - `sendInput(_ text: String)` → `send-keys -l -t %<pane> '<text with '\'' escaping>'`
   - `sendSpecialKey(_ key: String)` → `send-keys -t %<pane> <key>` (tmux key names: `Enter`, `C-c`, `Tab`, `Up`, `Down`, `Left`, `Right`, `BSpace`, `C-d`)
   - On SSH errors / transport close → transition to `.disconnected(error:)`
   (files: `MoriRemote/MoriRemote/SpikeCoordinator.swift`)

5. Create `SSHChannelTransport.swift` — adapter conforming `TmuxTransport` protocol, wrapping `SSHChannel` from `MoriSSH`:
   ```swift
   public struct SSHChannelTransport: TmuxTransport {
       let channel: SSHChannel
       public var inbound: AsyncThrowingStream<Data, Error> { channel.inbound }
       public func write(_ data: Data) async throws { try await channel.write(data) }
       public func close() async { await channel.close() }
   }
   ```
   (files: `MoriRemote/MoriRemote/SSHChannelTransport.swift`)

6. Create `KeyboardInputView.swift` — SwiftUI view with:
   - A `TextField` that captures keyboard text input, calls `coordinator.sendInput()` on submit
   - A row of special-key buttons: `Tab`, `↑`, `↓`, `←`, `→`, `Esc`, `Ctrl+C`, `Ctrl+D`
   - Each button calls `coordinator.sendSpecialKey()` with the tmux key name
   (files: `MoriRemote/MoriRemote/KeyboardInputView.swift`)

7. Wire up `MoriRemoteApp.swift` — app entry point:
   - Creates `SpikeCoordinator` as `@State`
   - NavigationStack: `ConnectView` → session name prompt → `TerminalView` + `KeyboardInputView`
   (files: `MoriRemote/MoriRemote/MoriRemoteApp.swift`)

8. Verify macOS app regression: `mise run build && mise run test` (all targets)

9. Build and run iOS app on simulator, perform manual end-to-end test against a real SSH host with tmux.

## Testing Strategy

### Unit Tests (executable targets, project convention)

- **`MoriSSHTests`**: auth config construction, error type coverage, mock transport verification
- **`MoriTmuxTests`** (extended):
  - Control-mode parser: `%output` with octal escapes (`\012` → newline, `\134` → backslash), high-bit bytes preserved verbatim, `%begin/%end/%error` command blocks with all 3 fields (timestamp/commandNumber/flags), notification parsing, non-`%` lines → `.plainLine`, unknown `%` lines → `.notification(.unknown(...))`
  - `TmuxControlClient` with mock `TmuxTransport`: send command → correlated `%begin/%end` response, `%error` → thrown error, line split across multiple data chunks, multiple lines in one chunk, transport EOF during pending command → disconnect error, `%output` routed to paneOutput stream

### Integration Tests (manual, spike validation)

- SSH connect to a real remote host (password auth)
- SSH connect with public key auth (stretch goal — import key data, not file path)
- `tmux -C new-session` over SSH exec channel → control-mode handshake (no DCS framing)
- `%output` bytes rendered in libghostty on iOS simulator
- Keyboard input reaches remote pane (`echo test`, `ls`, Ctrl+C)
- Session attach to existing session (`tmux -C attach-session -t <name>`)
- Verify `refresh-client -C` resizes the remote session to match iPhone renderer

### Regression Tests

- `mise run build` — macOS app builds without errors
- `mise run test` — all existing test suites pass
- `mise run test:core` — MoriCore cross-platform
- `mise run test:tmux` — MoriTmux macOS tests still pass (gated tests skipped on iOS)

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| libghostty pipe backend on iOS is undocumented/unstable | HIGH — blocks terminal rendering, spike marked partial if fails | Phase 4 step 2 is the hard gate. `UITextView` fallback is for transport/parser debugging only — does NOT satisfy spike success criteria. Pin ghostty revision. |
| GhosttyKit universal build fails (iOS SDK / Zig issues) | HIGH — blocks Phase 4+ | Test `--universal` build early in Phase 4. If blocked, build iOS slice separately. Keep `--native` default so macOS workflow is unaffected. |
| SwiftNIO SSH auth edge cases (key formats, passphrases) | MEDIUM — blocks connection | Start with password auth (simplest). Key auth is stretch goal using `Data` not file paths. Pin `swift-nio-ssh` 0.8.0+. Test against standard sshd. |
| tmux control-mode protocol edge cases | MEDIUM — corrupted state | Parse conservatively, log unknown lines as `.unknown`. Use `tmux -C` not `-CC` to avoid DCS framing. Test with real tmux 3.3+ output. |
| `#if os(macOS)` gating breaks existing imports or tests | LOW — build errors | Phase 1 includes test target audit. Run full build + test after each gating change. |
| Swift 6 strict concurrency with SwiftNIO | MEDIUM — compile errors | SwiftNIO SSH 0.8+ designed for Swift concurrency. Use actors consistently. |
| SSH disconnect/network change during session | LOW for spike | `SpikeCoordinator` transitions to `.disconnected(error:)`. No auto-reconnect. Display error. |

## Assumptions

- Development Mac has Xcode with iOS SDK installed (required for universal GhosttyKit build)
- A remote SSH host with tmux 3.3+ is available for manual integration testing
- The Ghostty submodule revision supports the pipe backend for iOS (`-Dapp-runtime=none`)
- SwiftNIO SSH 0.8.0+ API is stable enough for the spike
- tmux control-mode `%output` uses octal escaping as documented in tmux(1) and the Control Mode wiki
- User's `.tmux.conf` on the remote host does not interfere with control mode (if issues arise, spike can use `tmux -C -f /dev/null`)
- We use `tmux -C` (single-C) not `-CC`, avoiding DCS framing on the exec channel

## Review Feedback

### Round 1 (claude reviewer)

Integrated all feedback:
- **P0**: Added Phase 4 step 2 as explicit gate for libghostty iOS feasibility
- **P1**: Added SSH host key accept-all strategy with TODO comment (decision #10)
- **P1**: Specified `send-keys` escaping — single-quote with `'\''` for text, tmux key names for specials (decision #7)
- **P1**: Specified line buffering responsibility in `TmuxControlClient` (decision #4)
- **P1**: Completed `%output` octal escape specification in Phase 3 task 3
- **P1**: Detailed command correlation mechanism with `CheckedContinuation` dictionary (decision #5)
- **P2**: Fixed `%begin`/`%end` fields to use `timestamp`/`commandNumber` (Phase 3 task 1)
- **P2**: Pinned `swift-nio-ssh` 0.8.0+ (Phase 2 task 1)
- **P2**: Added test target audit task to Phase 1 (task 7)
- **P2**: Added disconnect error handling in `SpikeCoordinator` (decision #11, Phase 5 task 4)
- **P2**: Documented Xcode project rationale (decision #12)
- **P3**: Clarified keyboard input → tmux key mapping strategy (Phase 5 task 6)

### Round 2 (codex reviewer)

Integrated all feedback:
- **#1 `%output` octal spec**: Corrected — high-bit bytes (> 0x7E) preserved verbatim, only non-printable + backslash are octal-escaped. `\134` for backslash. Added high-bit byte test case. (decision #3, Phase 3 task 3/6)
- **#2 Parser statefulness / command correlation**: Parser is now explicitly stateless — returns `.plainLine(String)` for non-`%` lines. Block tracking moved to `TmuxControlClient`. Command number comes from server `%begin`, not local counter. Serialized one-at-a-time for spike. `%end`/`%error` carry 3 fields like `%begin`. (decision #5, Phase 3 tasks 1/3/5)
- **#3 `-CC` vs `-C` framing**: Switched to `tmux -C` (single-C) to avoid DCS `ESC P1000p` / `ESC \` framing. Added `refresh-client -C <cols>,<rows>` on attach and resize. (decisions #2, #8, Phase 5 task 4)
- **#4 Public key auth on iOS**: Reduced to stretch goal. Password auth is primary success criterion. Key auth uses `Data` (imported bytes), not filesystem paths. (decision #13, success criteria, Phase 2 task 2)
- **#5 Ghostty fallback**: Made libghostty a hard gate — spike is partial/blocked if it fails. `UITextView` only for transport debugging. (success criteria, risk table)
- **#6 Transport edge-case tests**: Added: line split across chunks, multiple lines in one chunk, pending-command cancellation on EOF, high-bit raw byte `%output`. (Phase 3 task 6)

## Final Status

(Updated after implementation completes — outcome, known issues, deviations from plan)
