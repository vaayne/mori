# Tasks: Mori Remote iOS — Phase 0 Spike

## Phase 1: Cross-Platform Package Foundation

- [x] 1.1 — Update `MoriCore/Package.swift` to add `.iOS(.v17)` platform (`Packages/MoriCore/Package.swift`)
- [x] 1.2 — Audit `MoriCore` sources for macOS-only APIs (`Packages/MoriCore/Sources/MoriCore/**/*.swift`)
- [x] 1.3 — Update `MoriTmux/Package.swift` to add `.iOS(.v17)` platform (`Packages/MoriTmux/Package.swift`)
- [x] 1.4 — Gate `TmuxCommandRunner.swift` behind `#if os(macOS)` (`Packages/MoriTmux/Sources/MoriTmux/TmuxCommandRunner.swift`)
- [x] 1.5 — Gate `TmuxBackend.swift` behind `#if os(macOS)` (`Packages/MoriTmux/Sources/MoriTmux/TmuxBackend.swift`)
- [x] 1.6 — Audit `PaneStateDetector.swift` and `AgentDetector.swift` — no gating needed (cross-platform)
- [x] 1.7 — Audit test targets and TmuxControlling — no gating needed (all cross-platform)
- [x] 1.8 — Verify macOS build + tests pass (`test:core` 361/361, `test:tmux` 200/200)

## Phase 2: MoriSSH Package — SSH Transport

- [x] 2.1 — Create `Packages/MoriSSH/Package.swift` with `swift-nio-ssh` 0.8.0+, `swift-nio` 2.65.0+ (`Packages/MoriSSH/Package.swift`)
- [x] 2.2 — Create `SSHAuthConfig.swift` — password + public key (Data, not path) auth types (`Packages/MoriSSH/Sources/MoriSSH/SSHAuthConfig.swift`)
- [x] 2.3 — Create `SSHConnectionManager.swift` — actor, TCP → SSH → auth → channels, accept-all host keys (`Packages/MoriSSH/Sources/MoriSSH/SSHConnectionManager.swift`)
- [x] 2.4 — Create `SSHChannel.swift` — async read/write wrapper over NIO channel (`Packages/MoriSSH/Sources/MoriSSH/SSHChannel.swift`)
- [x] 2.5 — Create `SSHError.swift` — error types (`Packages/MoriSSH/Sources/MoriSSH/SSHError.swift`)
- [x] 2.6 — Create `MoriSSHTests` executable test target (18/18 assertions pass)

## Phase 3: Tmux Control-Mode Client

- [ ] 3.1 — Create `TmuxControlLine.swift` — parsed line type enum with `.plainLine` (not `.commandResponse`) (`Packages/MoriTmux/Sources/MoriTmux/TmuxControlLine.swift`)
- [ ] 3.2 — Create `TmuxNotification.swift` — notification enum with `.unknown` (`Packages/MoriTmux/Sources/MoriTmux/TmuxNotification.swift`)
- [ ] 3.3 — Create `TmuxControlParser.swift` — stateless line parser with octal unescape, high-bit bytes verbatim (`Packages/MoriTmux/Sources/MoriTmux/TmuxControlParser.swift`)
- [ ] 3.4 — Create `TmuxTransport.swift` — byte channel protocol (`Packages/MoriTmux/Sources/MoriTmux/TmuxTransport.swift`)
- [ ] 3.5 — Create `TmuxControlClient.swift` — actor with line buffer, block tracking, serialized command correlation by server command number, EOF cancellation (`Packages/MoriTmux/Sources/MoriTmux/TmuxControlClient.swift`)
- [ ] 3.6 — Add parser + client tests: octal escapes, high-bit bytes, split chunks, multi-line chunks, EOF cancellation, `%error` (`Packages/MoriTmux/Tests/MoriTmuxTests/TmuxControlParserTests.swift`)

## Phase 4: GhosttyKit iOS Build + Terminal Bridge

- [ ] 4.1 — Update `scripts/build-ghostty.sh` with `--universal` flag (`scripts/build-ghostty.sh`)
- [ ] 4.2 — Build and validate universal xcframework (**HARD GATE**: if this fails, spike is blocked)
- [ ] 4.3 — Update `MoriTerminal/Package.swift` to add `.iOS(.v17)`, conditional `Carbon` linker setting (`Packages/MoriTerminal/Package.swift`)
- [ ] 4.4 — Gate all macOS-specific files behind `#if os(macOS)` (`Packages/MoriTerminal/Sources/MoriTerminal/*.swift`)
- [ ] 4.5 — Create `GhosttyiOSApp.swift` — iOS ghostty app singleton (`Packages/MoriTerminal/Sources/MoriTerminal/GhosttyiOSApp.swift`)
- [ ] 4.6 — Create `GhosttyPipeRenderer.swift` — UIView + pipe backend + CADisplayLink (`Packages/MoriTerminal/Sources/MoriTerminal/GhosttyPipeRenderer.swift`)

## Phase 5: iOS App Target + End-to-End Wiring

- [ ] 5.1 — Create `MoriRemote/` Xcode project with SPM package deps (`MoriRemote/`)
- [ ] 5.2 — Create `ConnectView.swift` — SSH connection form, password auth primary (`MoriRemote/MoriRemote/ConnectView.swift`)
- [ ] 5.3 — Create `TerminalView.swift` — UIViewRepresentable for GhosttyPipeRenderer (`MoriRemote/MoriRemote/TerminalView.swift`)
- [ ] 5.4 — Create `SpikeCoordinator.swift` — orchestrator: `tmux -C` (single-C), `refresh-client -C` on attach+resize, disconnect handling (`MoriRemote/MoriRemote/SpikeCoordinator.swift`)
- [ ] 5.5 — Create `SSHChannelTransport.swift` — TmuxTransport adapter for SSHChannel (`MoriRemote/MoriRemote/SSHChannelTransport.swift`)
- [ ] 5.6 — Create `KeyboardInputView.swift` — text input + special key buttons (`MoriRemote/MoriRemote/KeyboardInputView.swift`)
- [ ] 5.7 — Wire up `MoriRemoteApp.swift` — app entry point with navigation (`MoriRemote/MoriRemote/MoriRemoteApp.swift`)
- [ ] 5.8 — Verify macOS app regression (`mise run build && mise run test`)
- [ ] 5.9 — Build and run iOS app, manual end-to-end test including `refresh-client -C` resize
