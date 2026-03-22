# Codex Review: Mori Remote Plan

## Verdict

The project is technically feasible, but the current plan is optimistic in three places that will determine whether it succeeds:

1. Cross-platform packaging and code ownership
2. The remote protocol and reconnect state machine
3. iOS lifecycle constraints around suspension, resume, and background behavior

The ghostty fork + remote backend approach is plausible. The plan is weakest where it assumes the existing macOS-oriented Mori structure can absorb an iOS companion app without an explicit shared-core split.

## 1. Technical Feasibility And Soundness

### What looks sound

- Building a universal `GhosttyKit.xcframework` is feasible.
  - The vendored ghostty tree already contains UIKit surface support and iOS app code paths.
  - The current build script is already patching `GhosttyXCFramework.zig`, so switching from native-only output to universal output is directionally correct.

- A new ghostty `remote` termio backend is feasible.
  - `vendor/ghostty/src/termio/backend.zig` is currently a small tagged-union dispatch layer.
  - `vendor/ghostty/src/apprt/embedded.zig` exposes `ghostty_surface_config_new()` and an extensible `Surface.Options` struct, so adding remote fd fields is a reasonable integration point.

- A Mac host bridge built around `tmux attach-session` is feasible for an MVP.
  - It avoids inventing a terminal model.
  - It aligns with Mori’s current PTY-backed ghostty embedding on macOS.

- A Go websocket relay is a reasonable implementation choice for a small hosted component.

### Where the plan is technically incomplete

- The repo is currently macOS-first, not cross-platform.
  - Root [`Package.swift`](/Users/weliu/workspace/mori/Package.swift) is macOS-only.
  - [`Packages/MoriTerminal/Package.swift`](/Users/weliu/workspace/mori/Packages/MoriTerminal/Package.swift) is macOS-only.
  - [`Packages/MoriTerminal/Sources/MoriTerminal/GhosttyAdapter.swift`](/Users/weliu/workspace/mori/Packages/MoriTerminal/Sources/MoriTerminal/GhosttyAdapter.swift) and [`Packages/MoriTerminal/Sources/MoriTerminal/GhosttySurfaceView.swift`](/Users/weliu/workspace/mori/Packages/MoriTerminal/Sources/MoriTerminal/GhosttySurfaceView.swift) are AppKit-specific.
  - The plan should not assume “create a new Xcode project” is enough. It needs an explicit decision about what code becomes shared and what remains macOS-only.

- The iOS-side data path is underspecified.
  - If the remote backend reads terminal bytes from `read_fd` and writes user input or resize events to `write_fd`, the app needs two bridges:
    - websocket -> `read_fd`
    - `write_fd` -> websocket
  - Phase 5 currently only describes the first half clearly.

- The tmux interactive-mode design needs cleanup semantics.
  - Grouped sessions are a reasonable solution to size isolation.
  - But the plan does not define how grouped sessions are named, reattached, garbage-collected, or deduplicated across reconnects.
  - Without that, the host side will leak tmux sessions/windows over time.

- The plan assumes a 30-second background grace period on iOS.
  - That is not a safe assumption.
  - For a normal iOS app, suspension can happen quickly and unpredictably once backgrounded.
  - The system should be designed around detach/resume, not “stay alive for 30 seconds.”

## 2. Missing Steps Or Gaps

### Missing architecture work

- Add a shared protocol package before implementation.
  - Define message types, versioning, attach/detach flow, reconnect flow, heartbeat, error codes, and capability negotiation.
  - At minimum, introduce a small cross-platform module such as `MoriRemoteProtocol`.

- Add a shared session/auth model.
  - Decide where the iOS app stores the session ID and reconnect secret.
  - Use Keychain, not ephemeral in-memory state.
  - Define revocation and re-pairing behavior.

- Add a host-process ownership decision.
  - Should the Mac connector live inside the Mori app process, or as a separate helper?
  - If remote access should work while the UI is closed or not frontmost, embedding it directly in the app target is a weak default.

### Missing implementation steps

- Add a local harness for the remote backend before cloud work.
  - Example: a macOS or iOS sample surface that feeds canned VT bytes into the new backend and verifies rendering/input.
  - This should happen before the relay exists.

- Add a relay-free end-to-end harness.
  - Connector <-> local stub <-> iOS client loopback is enough to validate the protocol and fd bridge before Fly deployment.

- Add explicit websocket backpressure handling.
  - The plan mentions binary streaming but not bounded buffering, drop policy, or disconnect thresholds.
  - This matters more than the pipe buffer itself.

- Add heartbeat and idle timeout tasks.
  - Relying only on socket close detection will create stale pairings and slow failover.

- Add grouped-session cleanup tasks.
  - Test connect/disconnect loops.
  - Verify no stale grouped sessions remain after abrupt relay or app termination.

- Add localization work for all new user-facing strings.
  - The repo requires `.localized()` and both English and Simplified Chinese string entries.
  - The plan currently omits that entirely.

- Add docs and build integration work.
  - Update `README.md`, `CHANGELOG.md`, and `AGENTS.md`.
  - Add `mise` tasks for relay dev/test, iOS build/test, and any host helper workflows.

### Existing-repo mismatch that should be corrected

- Task `1.5 Add ghostty:sync mise task` is already done in [`mise.toml`](/Users/weliu/workspace/mori/mise.toml).
  - That is not new work.

- The plan says session names are raw `ws__project__worktree`.
  - That does not match the current repo.
  - Mori already uses human-readable tmux session names of the form `<project-short-name>/<branch-slug>` via [`Packages/MoriTmux/Sources/MoriTmux/SessionNaming.swift`](/Users/weliu/workspace/mori/Packages/MoriTmux/Sources/MoriTmux/SessionNaming.swift).
  - Do not create a parallel naming system unless there is a clear reason.

## 3. Risk Assessment Accuracy

### Risks that are understated

- Cross-platform packaging risk: high
  - This is one of the top risks, not a side note.
  - The existing package graph and terminal package are macOS-only. That split needs design work up front.

- Protocol and reconnect complexity: high
  - Session IDs, duplicate hosts, duplicate viewers, attach races, half-open sockets, and resume semantics are likely to cause more bugs than the relay transport itself.

- iOS suspension/lifecycle risk: high
  - The current risk table mentions app lifecycle indirectly, but it should be a first-class risk.
  - Expect abrupt background suspension and design for fast resume, not graceful long-lived background sessions.

- tmux state leakage in interactive mode: medium to high
  - Grouped sessions solve size coupling, but they introduce cleanup and reconciliation problems that are not currently called out.

- Security of long-lived reconnect credentials: high
  - The plan discusses pairing tokens and relay visibility, but not theft or replay of the reconnect credential stored on-device.

### Risks that are somewhat overstated or misprioritized

- CORS as a major protection
  - Origin checks are fine for browser abuse, but they do not materially secure native clients.
  - This should not appear as a core security mitigation.

- Pipe buffer saturation
  - Possible, but secondary.
  - Websocket buffering, renderer pacing, and reconnect correctness are more likely operational problems.

### Missing security and operational risks

- Token theft before first use
  - A QR token shown on-screen can be photographed or captured.
  - The threat model should say what happens if someone pairs first.

- Session replay after device compromise
  - If the session ID enables reconnect, its storage and invalidation policy matter.

- Payload exposure in crash dumps or debug logs
  - “No persistence” is not enough if logs, panic traces, or metrics include raw frames.

- Lack of device revocation
  - With no account system, there still needs to be a “forget this phone” mechanism on the Mac side.

## 4. Phase Ordering And Dependencies

The current ordering is serviceable, but not optimal for de-risking. The biggest unknown is not Fly.io deployment. It is whether ghostty on iOS works reliably with a new remote IO backend.

### Recommended ordering

1. Universal Ghostty build plus a minimal iOS shell app
2. Remote backend plus local loopback harness
3. Shared protocol package and explicit message/state-machine spec
4. Mac host connector against a local relay or direct loopback
5. Cloud relay deployment
6. QR pairing, session list, mode toggle, reconnect polish

### Why this ordering is better

- It proves the highest-risk technical assumption first: remote libghostty rendering on iOS.
- It forces protocol design before three components implement incompatible versions of it.
- It avoids spending time on Fly deployment and QR UX before the terminal path itself is working.

### Specific dependency corrections

- Phases 2 and 3 are not fully independent.
  - They can be partially parallelized only after the protocol and fd responsibilities are frozen.

- Phase 5 starts too late.
  - The iOS shell should begin much earlier, even if it initially renders canned bytes only.

- Fork hygiene should not block proof-of-concept work.
  - Forking and sync automation are useful, but they are not critical-path validation items.

## 5. Alternative Approaches Worth Considering

### Alternative 1: Reuse ghostty’s existing iOS wrappers more aggressively

Instead of building a fresh `UIViewRepresentable` from scratch, prefer reusing the vendored iOS ghostty wrapper types where possible:

- [`vendor/ghostty/macos/Sources/App/iOS/iOSApp.swift`](/Users/weliu/workspace/mori/vendor/ghostty/macos/Sources/App/iOS/iOSApp.swift)
- [`vendor/ghostty/macos/Sources/Ghostty/Surface View/SurfaceView_UIKit.swift`](/Users/weliu/workspace/mori/vendor/ghostty/macos/Sources/Ghostty/Surface%20View/SurfaceView_UIKit.swift)
- [`vendor/ghostty/macos/Sources/Ghostty/Surface View/SurfaceView.swift`](/Users/weliu/workspace/mori/vendor/ghostty/macos/Sources/Ghostty/Surface%20View/SurfaceView.swift)

That should reduce custom glue and keep the iOS rendering path closer to upstream ghostty behavior.

### Alternative 2: Use tmux control mode for metadata only

Keep raw `attach-session` for terminal bytes, but use tmux control mode or structured tmux commands for:

- session list
- window metadata
- active client state
- attach status

That is a better long-term control plane than inventing an ad hoc JSON layer that scrapes CLI output forever.

### Alternative 3: Separate host helper process

Consider a dedicated `MoriRemoteHost` helper instead of embedding all relay-host logic inside the main app target.

Benefits:

- cleaner lifecycle
- easier reconnect/relaunch behavior
- easier future launch-at-login or headless host mode
- less coupling to AppKit UI state

### Alternative 4: Pull encrypted payloads earlier if trust is a hard requirement

If relay trust is genuinely uncomfortable, E2E should move earlier in the roadmap. It does not need to be a final polished cryptosystem, but a simple payload encryption envelope would materially improve the security posture of an internet-facing terminal relay.

## Recommended Plan Changes

- Add a new Phase 0 for architecture and protocol definition.
  - deliverable: protocol spec
  - deliverable: host/client state diagrams
  - deliverable: storage and revocation decisions

- Split current Phase 5 into:
  - `5A` iOS shell app + Ghostty initialization + canned VT rendering
  - `5B` websocket/pipe bridge + remote backend integration

- Add explicit tasks for:
  - `write_fd -> websocket` bridge on iOS
  - heartbeat/ping and idle timeout
  - reconnect state-machine tests
  - grouped-session cleanup tests
  - real-device suspend/resume testing
  - Keychain storage and session invalidation
  - localization
  - docs updates

- Change task `4.3` from “map raw tmux names to display-friendly names” to “reuse existing `SessionNaming` and tmux domain models where possible.”

- Mark task `1.5` as already present, not net-new work.

## Bottom Line

The plan is credible, but it should be revised to treat remote ghostty IO, protocol definition, and iOS lifecycle behavior as the primary architecture drivers. If those are handled first, the relay and UI work are straightforward. If not, the project is likely to stall after meaningful effort has already gone into the cloud and pairing layers.
