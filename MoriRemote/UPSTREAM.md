# MoriRemote terminal transplant upstreams

## Pinned source

The Phase-1 terminal transplant is derived from `h3nock/remux` commit
[`b3a3e5f5dfa4759ab189e203b9a03749e821540c`](https://github.com/h3nock/remux/tree/b3a3e5f5dfa4759ab189e203b9a03749e821540c), inspected from `/tmp/remux-scout`.

`MoriRemoteTerminal` is a separate iOS 17 **static framework** target
(`MACH_O_TYPE = staticlib`). It links only Mori's
`../Frameworks/GhosttyKit.xcframework`; it has no package dependency and
exports the public `MoriRemoteTerminalSession` facade used by the production
SSH shell. The app target imports `MoriRemoteTerminal`, never `GhosttyKit`:
the static terminal archive is the sole native Ghostty owner. This is not a
permanent binary-distribution mechanism; the static archive supplies a module
boundary without embedding a second terminal dylib.

## Imported source boundary

The framework preserves upstream file and directory names for the terminal
core:

- `Tmux/`: identity, viewport, control protocol/link, session controller,
  terminal session, pane surface, screen adapter/model, pane preview cache,
  runtime trace, and deterministic test transport.
- `Ghostty/`: runtime/control and managed surfaces, pane/local viewport and
  scroll physics, key/mouse/scroll mappings, responder/text-input/focus/input
  coordination, modifier state, keyboard visibility/trackpad, the retained
  Ctrl/Esc/Tab/session/window/pane/system-keyboard chrome, preview layout,
  topology/selection projections, selection sheets, and
  `GhosttyTerminalCoreView` (the minimal upstream-derived composition root).
- `App/ActiveSessionSwitcherView.swift`: an account-free active-session
  switcher projection and view.
- `Domain/TerminalSettings.swift`: terminal appearance only.

The paired `MoriRemoteTerminalTests` target ports the matching upstream tests
for controller/session/link/adapter teardown, scrolling and viewport state,
responder and keyboard input, modifier state, selection projections, and the
active-session switcher.

## Explicit Phase-1 exclusions

No files from remux account/profile repositories, SSH services/transports,
SFTP/live forwarding, terminal preview, attachments, composer/voice, or
shortcut marketplace/editor are linked into `MoriRemoteTerminal`.

`TmuxControlTransport` is a terminal-internal protocol-only seam. The app
crosses it only through `MoriRemoteTerminalTransport`, whose byte lifecycle
closures are adapted by `SSHTmuxControlTransport.asTerminalTransport()`. This
omits remux SFTP and live-forward provider protocols. The deterministic
transport remains solely a terminal-core test fixture.

## Required adaptations and iOS 17 deviations

| Area | Change | Why |
| --- | --- | --- |
| `TmuxScreenModel.swift` | Reduced to injected `ghostty_app_t` + `TmuxControlTransport` composition. | Upstream constructs account targets, runtime status reporting, and preview services; those are Phase 2+ concerns. |
| `TmuxControlTransport.swift` | Protocol-only; removes SFTP/live-forward refinements. | Keeps the core independent of SSH/Citadel and forwarding. |
| `TmuxSessionController.swift` | Native client starts with `initial_columns = initial_rows = 0`; pane hydration derives dimensions from the authoritative tmux topology (window/pane grid), and exposes only fixed correlated agent-metadata query. | Prevents an implicit startup `refresh-client -C` or phone viewport dimensions from resizing the shared tmux client while keeping arbitrary tmux execution out of the app boundary. |
| `App/MoriRemoteTerminalFacade.swift` | Public deep facade owns `GhosttyKitRuntime` + screen model, exposes state/topology, fixed metadata results, labeled shared mutations, presentation lifecycle, and type-erased SSH byte lifecycle closures. | App code retains Citadel/trust/persistence without importing GhosttyKit or terminal controller/surface types. |
| `GhosttyTerminalDisconnectReasonClassifier.swift` | Transport-agnostic classifier. | No Phase-1 dependency on NIO, SSH errors, or host-trust types. |
| Runtime status types | Local terminal-only `TerminalRuntimeState` / disconnect vocabulary. | Avoids importing remux connection/account domain objects. |
| `GhosttySingleViewportView.swift` | 850-line subtractive adaptation of upstream's 883-line viewport. It retains local text-selection long press/update/end, selection handles and endpoint drag, selection-geometry recovery, copy edit-menu, surface tap/focus, horizontal window swipe, and mouse routing. | Preview candidate resolution/action is removed; copy remains. Picker sheets are topology UI, not text selection. |
| `GhosttyKeyboardChrome.swift` | Retains the actionable Ctrl/Esc/Tab, session/window/pane selectors, and system keyboard controls; removes composer and shortcut-store actions. | Those excluded surfaces require domains explicitly outside Phase 1. |
| `GhosttyTerminalCompositionState.swift` + `GhosttyTerminalCoreView.swift` | Small upstream-derived composition root over `TmuxTerminalScreenAdapter`; consumes keyboard notifications, visibility projection, viewport holds, responder callbacks, delayed prefix flush, viewport, text selection, cursor-trackpad HUD, chrome, and picker sheets. | No SSH construction or persistence dependency. |
| `ActiveSessionSwitcherView.swift` | Uses `UUID`/title/subtitle DTOs and select/disconnect callbacks. | Prevents profile/repository types from entering terminal core. |
| iOS 17 | Keeps `#available(iOS 26, *)` styling fallback in upstream selection UI; terminal framework deployment target is `17.0`. | Upstream source uses no required iOS 18 API in this closed slice. |

## Test provenance

The following table records the pinned upstream tests reviewed for each production
area and the local equivalent. “Adapted” means the assertion remains but was
made deterministic or detached from excluded remux domains.

| Production area | Pinned remux tests reviewed | MoriRemoteTerminalTests | Untranslated gap |
| --- | --- | --- | --- |
| tmux client/session/link/adapter | `TmuxSessionControllerClientSizeTests.swift`, `TmuxTerminalScreenAdapterTests.swift`, `TmuxTerminalSessionShutdownDrainTests.swift` | `MoriTmuxNativeStartupIsolationTests.swift`, `MoriTmuxIsolationTests.swift`, facade state/error tests, plus matching session/link/adapter tests | Native startup harness retains `GhosttyKitRuntime`, proves zero-grid startup emits version/list-windows but no `refresh-client`; facade failures complete fixed metadata queries; SSH transport integration remains excluded. |
| responder, text input and paste | `GhosttyTerminalResponderViewTests.swift`, `GhosttyTerminalInputCoordinatorTests.swift` | Same filenames | Simulator-global `UIPasteboard` integration replaced by injected deterministic source; routing remains tested. |
| keyboard visibility and viewport continuity | `GhosttyKeyboardVisibilityProjectionTests.swift` | `GhosttyKeyboardVisibilityProjectionTests.swift`, `GhosttyTerminalViewportCoordinatorTests.swift`, `GhosttyTerminalCompositionStateTests.swift` | No device keyboard-animation screenshot test. |
| delayed tmux prefix input | `GhosttyTerminalInputCoordinatorTests.swift` | `GhosttyTerminalInputCoordinatorTests.swift`, `GhosttyTerminalPrefixFlushLifecycleTests.swift` | Scheduler wall-clock timing is not asserted; token fencing and flush routing are deterministic. |
| local terminal selection/copy/gesture | `GhosttyKitControlSurfaceTests.swift`, `GhosttySurfaceMouseEventTests.swift`, `GhosttySurfaceScrollGestureTests.swift` | Same filenames | No end-to-end UIKit edit-menu presentation test; selection geometry, text decoding, mouse/tap and gesture reducers are deterministic. Preview-menu assertion is excluded with preview. |
| keyboard chrome | `GhosttyKeyboardChromeModeTests.swift` | `GhosttyKeyboardChromeModeTests.swift`, `GhosttyKeyboardChromeActionsTests.swift` | SwiftUI pixel/snapshot tests are not imported. |
| composition root | `GhosttySurfaceScreen.swift` (production call graph reviewed) | `GhosttyTerminalCoreViewTests.swift`, `GhosttyTerminalCompositionStateTests.swift` | Composer, attachments, shortcut UI and account actions deliberately excluded. |

## GhosttyKit provenance

Mori builds one untracked `Frameworks/GhosttyKit.xcframework` from the pinned
remux Ghostty source. It includes iOS arm64 device/simulator slices and exposes
the `ghostty_tmux_client_*` ABI used by the upstream controller. See
`ghosttykit-lock.json` and `scripts/verify-ghosttykit.sh` for the artifact
provenance and ABI checks.
