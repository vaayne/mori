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
- `76dbd46` — ♻️ refactor: fix Sendable warnings and clean up MoriSSH

**Decisions & context for next phase:**
- `SSHChannel` uses `@unchecked Sendable` since it wraps a NIO `Channel`. All writes go through `writeAndFlush` on the channel's event loop.
- `ExecHandler` inside `SSHConnectionManager.swift` fires `SSHChannelRequestEvent.ExecRequest` on `channelActive`. It feeds both stdout and stderr into the same inbound stream (sufficient for tmux control-mode which only uses stdout).
- `PasswordAuthDelegate` offers credentials once, then returns nil (matches `SimplePasswordDelegate` pattern). Uses `@unchecked Sendable` for mutable `offered` flag (safe: only accessed on event loop).
- Zero warnings in MoriSSH build — resolved by using concrete `PasswordAuthDelegate` type instead of protocol existential in closure capture.
- The `SSHChannel.write()` method wraps data in `SSHChannelData(type: .channel, data: .byteBuffer(...))` — correct encoding for remote exec channel stdin.
- Public key auth case exists in `SSHAuthMethod` but `SSHConnectionManager.connect()` throws `authenticationFailed` for it — stretch goal for later.
- RunLoop spinning approach for async tests in executable target context (avoids DispatchSemaphore deadlocks with Swift concurrency).
- Phase 3's `TmuxControlClient` will use `SSHChannel` via `TmuxTransport` protocol adapter (defined in MoriTmux, bridged in the iOS app).

### Fixes (post-review)
- **Auth wait**: `connect()` now installs `AuthCompletionHandler` that listens for `UserAuthSuccessEvent`. Returns only after auth succeeds; channel-close or errors before auth → `SSHError.authenticationFailed`. (commit `8fc51c2`)
- **Exec acceptance**: `ExecHandler` now handles `ChannelSuccessEvent` / `ChannelFailureEvent`. `openExecChannel()` waits for both child channel creation AND exec acceptance before returning `SSHChannel`. Server rejection → `SSHError.channelError`.
- **Test coverage**: 18 → 32 assertions. Added: SSHChannel inbound stream (single chunk, multi chunk, error propagation), write to inactive channel, close idempotency, publicKey auth rejection, unreachable host connection failure.
- **SSHChannel.init** made `public` for testability via `EmbeddedChannel`.
- **Package.swift** test target now depends on `NIOEmbedded`, `NIOCore`, `NIOSSH` for in-memory channel testing.

## Phase 3: Tmux Control-Mode Client

**Status:** complete

**Tasks completed:**
- 3.1: Created `TmuxControlLine` enum with `.output`, `.begin`, `.end`, `.error`, `.notification`, `.plainLine` cases. `Sendable`.
- 3.2: Created `TmuxNotification` enum with `sessionsChanged`, `sessionChanged`, `windowAdd`, `windowClose`, `windowRenamed`, `windowPaneChanged`, `layoutChanged`, `exit`, `unknown`. `Sendable` + `Equatable`.
- 3.3: Created `TmuxControlParser` — stateless line parser. `parse(_:)` maps one line to one `TmuxControlLine`. `unescapeOctal(_:)` handles `\ooo` sequences byte-by-byte; high-bit bytes preserved verbatim; non-octal `\` preserved as-is.
- 3.4: Created `TmuxTransport` protocol with `inbound: AsyncThrowingStream<Data, Error>`, `write(_:)`, `close()`. `Sendable`.
- 3.5: Created `TmuxControlClient` actor: line buffering over `Data`, `%begin/%end` block tracking, serialized command correlation via `CheckedContinuation`, EOF → `TmuxControlError.disconnected`. Routes `%output` to `paneOutput` stream and notifications to `notifications` stream.
- 3.6: Added 42 new test assertions (242 total). Parser tests: octal escapes (`\012`, `\134`), high-bit bytes (`\302\251`), all notification types, unknown lines, malformed blocks. Client tests: command success/error, line split across chunks, multi-line single chunk, EOF cancellation, pane output routing, notification routing, command newline termination.

**Files changed:**
- `Packages/MoriTmux/Sources/MoriTmux/TmuxControlLine.swift` — new: parsed line type enum
- `Packages/MoriTmux/Sources/MoriTmux/TmuxNotification.swift` — new: async notification enum
- `Packages/MoriTmux/Sources/MoriTmux/TmuxControlParser.swift` — new: stateless line parser with octal unescape
- `Packages/MoriTmux/Sources/MoriTmux/TmuxTransport.swift` — new: byte channel protocol
- `Packages/MoriTmux/Sources/MoriTmux/TmuxControlClient.swift` — new: control-mode client actor
- `Packages/MoriTmux/Tests/MoriTmuxTests/main.swift` — 42 new assertions (parser + client tests with MockTransport)

**Commits:**
- `d00a3ce` — ✨ feat: add TmuxControlLine enum for control-mode line types
- `2dd2afe` — ✨ feat: add TmuxNotification enum for async server events
- `a825089` — ✨ feat: add stateless TmuxControlParser with octal unescape
- `0708673` — ✨ feat: add TmuxTransport protocol for testable byte channel
- `b6b7519` — ✨ feat: add TmuxControlClient actor with line buffering and command correlation
- `d08c9ee` — ✅ test: add control-mode parser and client tests (42 new assertions)

**Decisions & context for next phase:**
- `TmuxControlParser` is a stateless `enum` (no instances) — same pattern as `TmuxParser`. One line in → one `TmuxControlLine` out. Block tracking is entirely in `TmuxControlClient`.
- `TmuxControlClient` uses `CheckedContinuation<String, any Error>` for command serialization. Only one command in-flight at a time (spike constraint). `pendingCommandNumber` tracks the server-assigned number from `%begin`.
- `TmuxControlError` is a separate error type from `TmuxError` — `TmuxError` is for Process-based tmux commands, `TmuxControlError` is for control-mode protocol issues.
- `MockTransport` in tests demonstrates the `TmuxTransport` protocol pattern. Phase 5's `SSHChannelTransport` will adapt `SSHChannel` (from MoriSSH) to this protocol.
- Tests use `RunLoop.current.run(mode:before:)` spinning with `nonisolated(unsafe) var asyncDone` to await async test code — same pattern established in MoriSSH tests for Swift 6 compatibility.
- `unescapeOctal` operates on raw UTF-8 bytes (`Array(escaped.utf8)`) so high-bit bytes pass through untouched. Tested with `\302\251` → `0xC2 0xA9` (©).
- The `paneOutput` stream type is `AsyncStream<(paneId: String, data: Data)>` — a tuple stream. Phase 5's `SpikeCoordinator` will consume this to feed bytes into the terminal renderer.
- All new files are cross-platform (no `#if os(macOS)` needed) — `TmuxControlClient` works on both macOS and iOS.

### Fixes (post-review)
- **sendCommand race**: Moved `pendingContinuation` registration before `transport.write()` so fast `%begin/%end` responses are correlated correctly. Write is now fire-and-forget via `Task`; write failures handled by transport EOF → `failPending()` path. (commit `ebb5b54`)
- **Regression test**: Added `FastResponseMockTransport` that feeds `%begin/response/%end` immediately during `write()` call. `testClientFastResponseRace` validates the fix. 242 → 243 assertions.

## Phase 4: GhosttyKit iOS Build + Terminal Bridge

**Status:** complete

**Tasks completed:**
- 4.1: Updated `scripts/build-ghostty.sh` to parse `--clean` and `--universal`, preserve native-by-default behavior, skip the native-only patch in universal mode, and explicitly validate iPhoneOS/iPhoneSimulator SDK availability.
- 4.2: Cherry-picked ghostty commit `a383d30aa` into `vendor/ghostty`, producing submodule HEAD `dfab86c51`. Built `Frameworks/GhosttyKit.xcframework` with `bash scripts/build-ghostty.sh --clean --universal` and verified the required slices: `macos-arm64_x86_64`, `ios-arm64`, and `ios-arm64-simulator`.
- 4.3: Added `.iOS(.v17)` to `Packages/MoriTerminal/Package.swift` and made `Carbon` link only on macOS with `.when(platforms: [.macOS])`.
- 4.4: Gated the listed macOS-only MoriTerminal source files with `#if os(macOS)` so AppKit/Carbon-only code is excluded from iOS builds.
- 4.5: Added `GhosttyiOSApp.swift`, a minimal `ghostty_app_t` singleton for iOS that initializes ghostty with a minimal config, installs wakeup/runtime stubs, and creates iOS surfaces with `GHOSTTY_PLATFORM_IOS`.
- 4.6: Added `GhosttyiOSRenderer.swift`, a `UIView`/`CAMetalLayer` host that creates a surface on demand, updates size and content scale, feeds remote bytes via `ghostty_surface_write_output`, reports grid size, and drives rendering with `CADisplayLink`.

**Files changed:**
- `scripts/build-ghostty.sh` — added `--universal` flag parsing, iOS SDK checks, universal/native target selection
- `vendor/ghostty` — submodule pointer updated to cherry-picked Manual backend commit `dfab86c51`
- `Packages/MoriTerminal/Package.swift` — added `.iOS(.v17)`, conditional `Carbon` linker setting
- `Packages/MoriTerminal/Sources/MoriTerminal/GhosttyApp.swift` — macOS-only gate
- `Packages/MoriTerminal/Sources/MoriTerminal/GhosttyAdapter.swift` — macOS-only gate
- `Packages/MoriTerminal/Sources/MoriTerminal/GhosttySurfaceView.swift` — macOS-only gate
- `Packages/MoriTerminal/Sources/MoriTerminal/GhosttyConfigFile.swift` — macOS-only gate
- `Packages/MoriTerminal/Sources/MoriTerminal/GhosttyConfigWriter.swift` — macOS-only gate
- `Packages/MoriTerminal/Sources/MoriTerminal/GhosttyThemeInfo.swift` — macOS-only gate
- `Packages/MoriTerminal/Sources/MoriTerminal/NativeTerminalAdapter.swift` — macOS-only gate
- `Packages/MoriTerminal/Sources/MoriTerminal/TerminalSurfaceCache.swift` — macOS-only gate
- `Packages/MoriTerminal/Sources/MoriTerminal/TerminalHost.swift` — macOS-only gate
- `Packages/MoriTerminal/Sources/MoriTerminal/ANSIParser.swift` — macOS-only gate
- `Packages/MoriTerminal/Sources/MoriTerminal/GhosttyiOSApp.swift` — new: minimal iOS ghostty app singleton
- `Packages/MoriTerminal/Sources/MoriTerminal/GhosttyiOSRenderer.swift` — new: iOS terminal renderer bridge
- `.agents/sessions/2026-03-28-mori-remote-spike/tasks.md` — Phase 4 checklist updated

**Verification:**
- `bash scripts/build-ghostty.sh --clean --universal` succeeded
- `swift build` in `Packages/MoriTerminal` succeeded on macOS with the rebuilt xcframework
- `mise run test:core` → 361 assertions passed
- `mise run test:tmux` → 243 assertions passed

**Commits:**
- `f88452d` — ✨ feat: add universal GhosttyKit build flag
- `136ca0e` — ✨ feat: add Ghostty iOS manual backend
- `dc4c43f` — ✨ feat: add iOS platform to MoriTerminal package
- `24c3625` — ♻️ refactor: gate macOS terminal sources by platform
- `cfeea1e` — ✨ feat: add Ghostty iOS app singleton
- `44361b2` — ✨ feat: add Ghostty iOS renderer bridge

**Decisions & context for next phase:**
- The original plan’s “pipe backend” was replaced by the cherry-picked Manual backend; `GhosttyiOSRenderer.feedBytes(_:)` uses `ghostty_surface_write_output`, which is the correct embedding API from `dfab86c51`.
- `GhosttyiOSApp` intentionally does not load user config files. It finalizes an empty config so iOS avoids `~/.config` assumptions and starts with the minimal embedded defaults from ghostty itself.
- `GhosttyiOSRenderer` is intentionally minimal: no keyboard/input, clipboard, IME, or selection support. Phase 5’s coordinator can feed SSH/tmux output in and use `gridSize()` for `refresh-client -C`.
- A direct `swift build --triple arm64-apple-ios17.0-simulator` attempt from the CLI failed in this environment with `unable to load standard library for target 'arm64-apple-ios17.0-simulator'`, which appears to be host toolchain/sysroot wiring rather than a MoriTerminal source error. The universal xcframework itself built successfully with the iOS slices present.

### Fixes (post-review, pre-reviewer)
- **Incomplete macOS gating**: Four files (`GhosttyApp.swift`, `GhosttySurfaceView.swift`, `NativeTerminalAdapter.swift`, `ANSIParser.swift`) had `#if os(macOS)` only around imports/initial types — class/struct bodies were exposed. Moved `#endif` to end of each file. (commit `cb0d103`)
- **iOS build errors (reviewer finding #1)**: Fixed 3 compilation errors in iOS Simulator build:
  - `GhosttyiOSApp.swift`: `strdup` argv array type — used `[UnsafeMutablePointer<CChar>?]` and passed `baseAddress!` directly to `ghostty_init` (matches `char**` → `UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>`)
  - `GhosttyiOSRenderer.swift`: `bytes.count` → `UInt(bytes.count)` for `ghostty_surface_write_output` length
  - `GhosttyiOSRenderer.swift`: `deinit` wrapped in `MainActor.assumeIsolated` for Swift 6 strict concurrency
  - Verified: `xcodebuild -scheme MoriTerminal -destination 'generic/platform=iOS Simulator' build` → BUILD SUCCEEDED (commit `b2df89f`)
- **Build script cache validation (reviewer finding #2)**: `--universal` now checks for `ios-arm64` and `ios-arm64-simulator` slices in cached xcframework; rebuilds if missing (commit `b2df89f`)

## Phase 5: iOS App Target + End-to-End Wiring

**Status:** implemented; simulator build passes, manual remote end-to-end validation pending

**Tasks completed:**
- 5.1: Created `MoriRemote/` with an XcodeGen-backed iOS app project, generated `MoriRemote.xcodeproj`, added `Info.plist`, asset catalog, and local package dependencies on `MoriCore`, `MoriTmux`, `MoriSSH`, and `MoriTerminal`.
- 5.2: Added `ConnectView.swift` with host, port, username, password, connect action, and disconnected-state error display.
- 5.3: Added `TerminalView.swift` with a `UIViewRepresentable` container around `GhosttyiOSRenderer`, exposing renderer-ready and resize callbacks back to the coordinator.
- 5.4: Added `SpikeCoordinator.swift` as an `@MainActor @Observable` orchestration layer for SSH connect, tmux attach, pane-output streaming, resize-driven `refresh-client -C`, tmux exit handling, and input dispatch.
- 5.5: Added `SSHChannelTransport.swift` as the `TmuxTransport` adapter for `SSHChannel`.
- 5.6: Added `KeyboardInputView.swift` with text submission and special-key buttons (`Tab`, arrows, `Esc`, `Ctrl+C`, `Ctrl+D`).
- 5.7: Wired `MoriRemoteApp.swift` with connect → session attach → terminal flow, plus app-local localization helpers/resources.
- 5.8: Verified macOS regressions with `mise run test:core` (361 assertions passed) and `mise run test:tmux` (243 assertions passed).
- 5.9: Built the iOS app for the arm64 simulator with `xcodebuild -project MoriRemote.xcodeproj -scheme MoriRemote -sdk iphonesimulator -arch arm64 build`.

**Files changed:**
- `MoriRemote/project.yml` — XcodeGen source of truth for the iOS target, package deps, and simulator arch constraint
- `MoriRemote/MoriRemote.xcodeproj/project.pbxproj` — generated iOS app project
- `MoriRemote/MoriRemote/Info.plist` — minimal SwiftUI app plist
- `MoriRemote/MoriRemote/Assets.xcassets/**` — app asset catalog scaffold
- `MoriRemote/MoriRemote/ConnectView.swift` — SSH connect form
- `MoriRemote/MoriRemote/TerminalView.swift` — renderer bridge
- `MoriRemote/MoriRemote/SpikeCoordinator.swift` — SSH/tmux/renderer coordinator
- `MoriRemote/MoriRemote/SSHChannelTransport.swift` — SSHChannel adapter
- `MoriRemote/MoriRemote/KeyboardInputView.swift` — text + special key input
- `MoriRemote/MoriRemote/MoriRemoteApp.swift` — app entry and screen flow
- `MoriRemote/MoriRemote/Resources/en.lproj/Localizable.strings` — English strings for the iOS spike UI
- `MoriRemote/MoriRemote/Resources/zh-Hans.lproj/Localizable.strings` — Simplified Chinese strings for the iOS spike UI
- `CHANGELOG.md` — unreleased feature note for the iOS remote spike app
- `.agents/sessions/2026-03-28-mori-remote-spike/tasks.md` — Phase 5 checklist updated

**Verification:**
- `xcodegen generate` in `MoriRemote/` succeeded
- `xcodebuild -project MoriRemote.xcodeproj -scheme MoriRemote -sdk iphonesimulator -arch arm64 build` succeeded
- `mise run test:core` → 361 assertions passed
- `mise run test:tmux` → 243 assertions passed

**Manual validation steps still needed:**
- Launch the generated `MoriRemote` app in Xcode or Simulator on an Apple Silicon Mac (`arm64` simulator only; the checked-in GhosttyKit simulator slice does not include `x86_64`).
- Connect to a reachable SSH host with tmux installed.
- Attach to a session name and confirm the first pane renders in the terminal surface.
- Type text plus special keys and verify remote pane input lands via tmux `send-keys`.
- Rotate or resize the simulator/device and confirm the remote client receives updated dimensions via `refresh-client -C`.

**Decisions & context for next phase:**
- `MoriRemote.xcodeproj` is generated from `MoriRemote/project.yml` using `xcodegen`; update the spec and re-run generation rather than hand-editing `project.pbxproj`.
- `SpikeCoordinator` serializes all tmux commands through `runTmuxCommand(_:)` because `TmuxControlClient` intentionally allows only one in-flight command; this avoids resize/input races.
- The app currently renders only the first pane ID returned by `list-panes -F '#{pane_id}'`, which matches the spike scope.
- The simulator build excludes `x86_64` because the Phase 4 `GhosttyKit.xcframework` only provides an `ios-arm64-simulator` slice. Intel simulator support would require rebuilding GhosttyKit with an x86_64 simulator slice.
- Manual end-to-end validation was not possible in this environment because no test SSH/tmux endpoint was available.
