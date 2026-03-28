# Handoff

<!-- Append a new phase section after each phase completes. -->

## Phase 1: Cross-Platform Package Foundation

**Status:** complete

**Tasks completed:**
- 1.1: Added `.iOS(.v17)` platform to `MoriCore/Package.swift`
- 1.2: Audited all MoriCore sources — no macOS-only APIs found. `SSHCommandSupport.swift` uses `CryptoKit`, `Darwin`, `Foundation` (all cross-platform). No `Process` usage in this file despite the plan's NOTE suggesting otherwise.
- 1.3: Added `.iOS(.v17)` platform to `MoriTmux/Package.swift`
- 1.4: Gated `SendableResumeGuard` and `TmuxCommandRunner` actor behind `#if os(macOS)`. Kept `TmuxSSHConfig` typealias and `TmuxError` enum cross-platform (required by `TmuxControlling.swift`).
- 1.5: Gated entire `TmuxBackend` actor behind `#if os(macOS)` (depends on `TmuxCommandRunner`).
- 1.6: Audited `PaneStateDetector.swift` and `AgentDetector.swift` — both use only `Foundation` and cross-platform types. No gating needed.
- 1.7: Audited `TmuxControlling.swift` protocol and test targets. `TmuxControlling` kept cross-platform for Phase 3 iOS use. Tests only reference cross-platform types (`TmuxParser`, `TmuxSession`, `TmuxPane`, `SessionNaming`, `PaneStateDetector`, `AgentDetector`). No gating needed.
- 1.8: Verified macOS build + tests pass: `test:core` 361/361 assertions, `test:tmux` 200/200 assertions.

**Files changed:**
- `Packages/MoriCore/Package.swift` — added `.iOS(.v17)` platform
- `Packages/MoriTmux/Package.swift` — added `.iOS(.v17)` platform
- `Packages/MoriTmux/Sources/MoriTmux/TmuxCommandRunner.swift` — `#if os(macOS)` around `SendableResumeGuard` + `TmuxCommandRunner`; `TmuxSSHConfig` and `TmuxError` remain cross-platform
- `Packages/MoriTmux/Sources/MoriTmux/TmuxBackend.swift` — `#if os(macOS)` around entire `TmuxBackend` actor
- `.agents/sessions/2026-03-28-mori-remote-spike/tasks.md` — task checklist updated

**Commits:**
- `4729529` — ✨ feat: add iOS 17+ platform to MoriCore package
- `35c0b78` — ✨ feat: add iOS 17+ platform to MoriTmux package
- `c727acb` — ♻️ refactor: gate TmuxCommandRunner behind #if os(macOS)
- `12279be` — ♻️ refactor: gate TmuxBackend behind #if os(macOS)

**Decisions & context for next phase:**
- `TmuxError` and `TmuxSSHConfig` are deliberately kept outside `#if os(macOS)` in `TmuxCommandRunner.swift` because `TmuxControlling.swift` (cross-platform) depends on them. If a future refactor moves these to a dedicated file, update the gate boundary.
- `TmuxControlling` protocol stays cross-platform — Phase 3's `TmuxControlClient` can conform to it on iOS.
- `PaneStateDetector`, `AgentDetector`, `TmuxParser`, `SessionNaming`, `TmuxSession`, `TmuxWindow`, `TmuxPane`, `PaneState`, `PaneDirection` are all cross-platform. Tests exercise only these types, so they work on both platforms.
- `SSHCommandSupport.swift` compiles on iOS but `createAskPassScript()` and `askPassEnvironment()` are macOS-oriented (shell-based SSH askpass). Phase 2's `MoriSSH` package will use SwiftNIO SSH directly, not these helpers. Consider gating them in a future cleanup if they confuse the iOS API surface.
- The full `mise run build` fails due to missing `GhosttyKit.xcframework` (not built in this environment), but this is unrelated to Phase 1 changes. Package-level builds (`swift build` in MoriCore/MoriTmux directories) succeed.

## Phase 2: MoriSSH Package — SSH Transport

**Status:** complete

**Tasks completed:**
- 2.1: Created `Packages/MoriSSH/Package.swift` with `swift-nio-ssh` 0.8.0+ (resolved to 0.12.0), `swift-nio` 2.65.0+ (resolved to 2.97.1), platforms macOS 14+ / iOS 17+.
- 2.2: Created `SSHAuthMethod` enum with `.password(String)` and `.publicKey(privateKey: Data, passphrase: String?)` cases. Key data as `Data` (not file path) for iOS sandbox compatibility.
- 2.3: Created `SSHConnectionManager` actor with `connect(host:port:user:auth:)`, `openExecChannel(command:)`, `disconnect()`, `isConnected`. Password auth via `PasswordAuthDelegate`. Accept-all host keys for spike (TODO: TOFU). Uses `MultiThreadedEventLoopGroup` for both platforms.
- 2.4: Created `SSHChannel` class (renamed from `SSHExecChannel`) with `inbound: AsyncThrowingStream<Data, Error>` and `write(_ data: Data)`. Separate `SSHChannelDataHandler` for NIO channel pipeline.
- 2.5: Created `SSHError` enum with `connectionFailed`, `authenticationFailed`, `timeout`, `channelError`, `disconnected`. Conforms to `Error`, `Sendable`, `LocalizedError`.
- 2.6: Created `MoriSSHTests` executable test target: auth config construction, error descriptions, manager initial state, manager open-exec-without-connect. 18/18 assertions pass.

**Files changed:**
- `Packages/MoriSSH/Package.swift` — new package with NIOSSH + NIOCore + NIOPosix deps
- `Packages/MoriSSH/Sources/MoriSSH/SSHAuthConfig.swift` — `SSHAuthMethod` enum
- `Packages/MoriSSH/Sources/MoriSSH/SSHError.swift` — `SSHError` enum
- `Packages/MoriSSH/Sources/MoriSSH/SSHChannel.swift` — `SSHChannel` class + `SSHChannelDataHandler`
- `Packages/MoriSSH/Sources/MoriSSH/SSHConnectionManager.swift` — `SSHConnectionManager` actor + auth/host-key delegates + `ExecHandler`
- `Packages/MoriSSH/Tests/MoriSSHTests/Assert.swift` — test helpers (copied from MoriTmux pattern)
- `Packages/MoriSSH/Tests/MoriSSHTests/main.swift` — executable test target

**Commits:**
- `e4879a9` — ✨ feat: create MoriSSH package with swift-nio-ssh dependency
- `b972aaf` — ✨ feat: add SSHAuthMethod enum
- `0cdaec0` — ✨ feat: add SSHError enum
- `d0f1a1d` — ✨ feat: add SSHChannel with async inbound stream
- `88bd9cf` — ✨ feat: add SSHConnectionManager actor
- `f7c9504` — ✅ test: add MoriSSHTests executable test target

**Decisions & context for next phase:**
- `SSHChannel` uses `@unchecked Sendable` since it wraps a NIO `Channel` (not Sendable by design). All writes are routed through the event loop.
- `ExecHandler` inside `SSHConnectionManager.swift` fires `SSHChannelRequestEvent.ExecRequest` on `channelActive`. It feeds both stdout and stderr into the same inbound stream (sufficient for tmux control-mode which only uses stdout).
- NIO SSH warnings about non-Sendable types (`NIOSSHHandler`, `NIOSSHClientUserAuthenticationDelegate`) are expected — these are NIO's own types that haven't been fully updated for Swift 6.
- The `SSHChannel.write()` method wraps data in `SSHChannelData(type: .channel, data: .byteBuffer(...))` — this is the correct encoding for sending data to a remote exec channel's stdin.
- Public key auth case exists in `SSHAuthMethod` but `SSHConnectionManager.connect()` throws `authenticationFailed` for it — stretch goal for later.
- `Task.detached` used in tests to avoid Swift 6 Sendable closure capture warnings. RunLoop spinning approach to wait for async tests in executable target context.
- Phase 3's `TmuxControlClient` will use `SSHChannel` via `TmuxTransport` protocol adapter (defined in MoriTmux, bridged in the iOS app).
