# MoriRemote remux upstreams

## remux GhosttyKit (release artifact contract)

MoriRemote's remux rewrite probe uses a separately installed, **untracked**
XCFramework at `Frameworks/RemuxGhosttyKit.xcframework`. It is intentionally
not the macOS framework at `Frameworks/GhosttyKit.xcframework` and must never
replace it.

| Field | Value |
| --- | --- |
| Release asset | `GhosttyKit.xcframework.zip` |
| Release tag | `ghosttykit-20260731` |
| SHA-256 | `e54ca81edf40721f72e87b5a5449746cd8fdcc877d5b0f284cdf2e34609f21f9` |
| Asset repository | <https://github.com/h3nock/remux-ghostty> |
| Asset source commit | `aeb8f73790946d9c9ad175b3dafaec9911ef36bb` |
| Reference application | <https://github.com/h3nock/remux> at `b3a3e5f5dfa4759ab189e203b9a03749e821540c` |

Install it for local development with `scripts/fetch-remux-ghosttykit.sh`, then
validate it with `scripts/verify-remux-ghosttykit.sh`. The scripts enforce the
pinned archive SHA-256 **and** a source-controlled digest of every installed
framework file, require iOS arm64 device and simulator slices, and check the
custom tmux C ABI before any build.

A release build must instead run
`MORI_REMUX_GHOSTTYKIT_MIRROR_URL=<Mori-controlled URL> bash scripts/fetch-remux-ghosttykit.sh --require-mirror`.
This fails closed when the variable is absent; it never falls back to an
upstream maintainer's asset. The mirror URL may not override the release tag,
archive checksum, source commit, or installed-tree digest.

**Remaining operator step before TestFlight:** upload the byte-identical
`GhosttyKit.xcframework.zip` whose SHA-256 is
`e54ca81edf40721f72e87b5a5449746cd8fdcc877d5b0f284cdf2e34609f21f9` to a
Mori-controlled release location, set the repository variable
`MORI_REMUX_GHOSTTYKIT_MIRROR_URL` to that exact HTTPS asset URL, and trigger
CI once. Do not change a checksum to accommodate another binary. This checkout
has no configured Mori-controlled asset, so TestFlight remains intentionally
blocked.

The framework derives from Ghostty as modified by `h3nock/remux-ghostty`.
Ghostty and the adapted remux source are MIT licensed; complete distributed
notices are in [`../THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md).

## Citadel / NIOSSH package identity (Phase 2)

MoriRemote pins h3nock/Citadel at `1d0eadd81d0a521b00ede6663c8b3301f5fc252e`.
Citadel pins h3nock's `swift-nio-ssh` fork at
`7588777b8f6439efa1a33117f86cb2729abd864c`. MoriRemote no longer links the legacy `MoriSSH` package. The fork remains a
direct MoriRemote dependency because Citadel uses that exact `NIOSSH` module;
macOS package resolution is independent and must not be changed as a side
effect of an iOS artifact update.

## Phase 3 Ghostty tmux core slice

The reference is `h3nock/remux` commit
`b3a3e5f5dfa4759ab189e203b9a03749e821540c`. The initial Mori adaptation is
intentionally limited to the native runtime and control boundary:

| Mori production file | Upstream production reference | Upstream test reference | Mori coverage / deviation |
| --- | --- | --- | --- |
| `Ghostty/GhosttyKitRuntime.swift` | `Ghostty/GhosttyKitRuntime.swift` | `GhosttyKitRuntimeTests.swift` | iOS 17 runtime/app ownership only; settings/theme warmup is deferred with the shell. |
| `Tmux/TmuxSessionController.swift` | `Tmux/TmuxSessionController.swift` | `TmuxSessionControllerClientSizeTests.swift` | One writer queue owns every client call, parser action, command token, outbound consume, native surface notification, topology revision, and retained canonical terminal. `Phase3RuntimeTests` translates the local history, topology projection, command admission, tracked-input failure, shutdown, and surface-fence contracts. Deliberately omits upstream `refresh-client -C`, `resize-pane -Z`, zoom, and server copy-mode commands. |
| `Tmux/TmuxControl.swift` | `Tmux/TmuxSessionLink.swift` | `TmuxSessionLinkWriteFailureTests.swift` | Adds a narrow `beforeReceive` gate: the client is created after SSH attach but before inbound pumping, preventing startup bytes from bypassing Ghostty. `DeterministicTmuxControlTransport` adds delayed chunks, terminal errors, and captured writes for those tests. |
| `Ghostty/GhosttyTmuxRuntime.swift` | `Tmux/TmuxTerminalSession.swift` | `GhosttyRuntimeSurfaceTopologySnapshotTests.swift` | One-shot runtime composition, callback instance fence, and stop order (link → every unregister fence → controller shutdown). `GhosttyRuntimeCallbackGate` is tested as a pure projection because a fabricated C surface would make a false ABI claim. |
| `Ghostty/GhosttyTerminalProbe.swift` | debug terminal fixture patterns | n/a | DEBUG-only deterministic route (`--ghostty-terminal-probe`); it does not replace the production root or require credentials. |

The upstream managed surface, responder, input, viewport, and scrolling files
were reviewed but not copied wholesale. `Ghostty/GhosttyPaneSurface.swift`
provides the local-only iOS 17 adaptation: CAMetal rendering, native surface
registration fences, hardware/software keyboard and IME input, paste,
selection/copy, and bounded local scrolling. It deliberately omits remux's
server zoom, server copy-mode browsing, and viewport resize commands because
those would violate MoriRemote's isolated-client invariants.
