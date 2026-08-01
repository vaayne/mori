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
  coordination, modifier state, keyboard visibility/trackpad, compact keypad
  and system-keyboard chrome, preview layout, topology/selection projections,
  selection sheets, and `GhosttyTerminalCoreView` (the minimal
  upstream-derived composition root).
- `Domain/TerminalSettings.swift`: terminal appearance only.

The paired `MoriRemoteTerminalTests` target ports the matching upstream tests
for controller/session/link/adapter teardown, scrolling and viewport state,
responder and keyboard input, modifier state, and selection projections.

## Explicit exclusions

No files from remux account/profile repositories, SSH services/transports,
live forwarding, terminal preview, full composer/voice, generic file
attachments, or shortcut marketplace/editor are linked into
`MoriRemoteTerminal`. Image input is the deliberate exception: the terminal
module owns photo/clipboard staging and preview UI, while a narrow
`MoriRemoteTerminalImageUploader` facade delegates the authenticated SFTP
upload to Mori's app-owned SSH root pool.

`TmuxControlTransport` remains a terminal-internal protocol-only seam. The app
crosses it only through `MoriRemoteTerminalTransport`, whose byte lifecycle
closures are adapted by `SSHTmuxControlTransport.asTerminalTransport()`.
Image upload is a separate typed operation and cannot execute arbitrary tmux or
shell commands; it atomically uploads below `~/.cache/mori/attachments` and
inserts a shell-escaped path without pressing Enter. The deterministic
transport remains solely a terminal-core test fixture.

## Required adaptations and iOS 17 deviations

| Area | Change | Why |
| --- | --- | --- |
| `TmuxScreenModel.swift` | Reduced to injected `ghostty_app_t` + `TmuxControlTransport` composition. | Upstream constructs account targets, runtime status reporting, and preview services; those are Phase 2+ concerns. |
| `TmuxControlTransport.swift` | Protocol-only; removes SFTP/live-forward refinements. | Keeps the core independent of SSH/Citadel and forwarding. |
| `TmuxSessionController.swift` | Native client starts with `initial_columns = initial_rows = 0`; pane hydration derives dimensions from the authoritative tmux topology (window/pane grid), and exposes only fixed correlated agent-metadata query. | Prevents an implicit startup `refresh-client -C` or phone viewport dimensions from resizing the shared tmux client while keeping arbitrary tmux execution out of the app boundary. |
| `App/MoriRemoteTerminalFacade.swift` | Public deep facade owns `GhosttyKitRuntime` + screen model, exposes state/topology, fixed metadata results, labeled shared mutations, presentation lifecycle, type-erased SSH byte lifecycle closures, and one typed image-uploader closure. | App code retains Citadel/trust/persistence/SFTP without importing GhosttyKit or terminal controller/surface types. |
| `GhosttyTerminalDisconnectReasonClassifier.swift` | Transport-agnostic classifier. | No Phase-1 dependency on NIO, SSH errors, or host-trust types. |
| Runtime status types | Local terminal-only `TerminalRuntimeState` / disconnect vocabulary. | Avoids importing remux connection/account domain objects. |
| `GhosttySingleViewportView.swift` | 850-line subtractive adaptation of upstream's 883-line viewport. It retains local text-selection long press/update/end, selection handles and endpoint drag, selection-geometry recovery, copy edit-menu, surface tap/focus, horizontal window swipe, and mouse routing. | Preview candidate resolution/action is removed; copy remains. Picker sheets are topology UI, not text selection. |
| `TmuxPaneSurface.swift` + `GhosttyPublishedFrameObserver.swift` | Adds a post-publication interaction-state refresh when Ghostty replaces the renderer layer contents. | The pinned upstream callback polls scrollbar state immediately after `terminalChanged`, before the renderer necessarily applies new output. Without the completed-frame refresh, UIKit can retain an undersized local scroll document and stop above the true bottom. |
| `GhosttyKeyboardChrome.swift` + `GhosttyKeypadSheet.swift` + `GhosttyImageAttachmentSheet.swift` | Keeps remux's trailing keyboard placement in a slim four-icon input accessory, combines terminal shortcuts in one categorized keypad, and exposes remux-derived photo/clipboard image staging from that panel. App-owned and image-picker modal presentation suspends the hidden terminal responder. | Stable controls avoid localized-label drift; responder suspension protects text fields and system pickers; confirmed images upload through the typed facade and insert only an escaped path. Full composer/voice and shortcut-store domains remain excluded. |
| `GhosttyTerminalCompositionState.swift` + `GhosttyTerminalCoreView.swift` | Small upstream-derived composition root over `TmuxTerminalScreenAdapter`; consumes keyboard notifications, visibility projection, viewport holds, responder callbacks, delayed prefix flush, viewport, text selection, cursor-trackpad HUD, and chrome. | Host/session/window/pane navigation belongs to Mori's app boundary, where server discovery and metadata already live. |
| iOS 17 | Keeps `#available(iOS 26, *)` styling fallback in upstream selection UI; terminal framework deployment target is `17.0`. | Upstream source uses no required iOS 18 API in this closed slice. |

## Test provenance

The following table records the pinned upstream tests reviewed for each production
area and the local equivalent. “Adapted” means the assertion remains but was
made deterministic or detached from excluded remux domains.

| Production area | Pinned remux tests reviewed | MoriRemoteTerminalTests | Untranslated gap |
| --- | --- | --- | --- |
| tmux client/session/link/adapter | `TmuxSessionControllerClientSizeTests.swift`, `TmuxTerminalScreenAdapterTests.swift`, `TmuxTerminalSessionShutdownDrainTests.swift` | `MoriTmuxNativeStartupIsolationTests.swift`, `MoriTmuxIsolationTests.swift`, facade state/error tests, plus matching session/link/adapter tests | Native startup harness retains `GhosttyKitRuntime`, proves zero-grid startup emits version/list-windows but no `refresh-client`; facade failures complete fixed metadata queries; SSH transport integration remains excluded. |
| responder, text input and paste | `GhosttyTerminalResponderViewTests.swift`, `GhosttyTerminalInputCoordinatorTests.swift` | Same filenames, plus marked-text composition coverage | Simulator-global text pasteboard integration is injected; IME marked text remains local and commits once through insert/replace/unmark. |
| keyboard visibility and viewport continuity | `GhosttyKeyboardVisibilityProjectionTests.swift` | `GhosttyKeyboardVisibilityProjectionTests.swift`, `GhosttyTerminalViewportCoordinatorTests.swift`, `GhosttyTerminalCompositionStateTests.swift` | No device keyboard-animation screenshot test. |
| delayed tmux prefix input | `GhosttyTerminalInputCoordinatorTests.swift` | `GhosttyTerminalInputCoordinatorTests.swift`, `GhosttyTerminalPrefixFlushLifecycleTests.swift` | Scheduler wall-clock timing is not asserted; token fencing and flush routing are deterministic. |
| local terminal selection/copy/gesture | `GhosttyKitControlSurfaceTests.swift`, `GhosttySurfaceMouseEventTests.swift`, `GhosttySurfaceScrollGestureTests.swift` | Same filenames | No end-to-end UIKit edit-menu presentation test; selection geometry, text decoding, mouse/tap and gesture reducers are deterministic. Preview-menu assertion is excluded with preview. |
| keyboard chrome | `GhosttyKeyboardChromeModeTests.swift` | `GhosttyKeyboardChromeModeTests.swift`, `GhosttyKeyboardChromeActionsTests.swift` | SwiftUI pixel/snapshot tests are not imported. |
| composition root | `GhosttySurfaceScreen.swift` (production call graph reviewed) | `GhosttyTerminalCoreViewTests.swift`, `GhosttyTerminalCompositionStateTests.swift`, `GhosttyImageAttachmentTests.swift`, app-side `ImageInputTests.swift` | Full composer/voice, generic files, shortcut UI and account actions remain excluded; image path formatting and atomic upload ordering are deterministic. |

## GhosttyKit provenance

Mori builds one untracked `Frameworks/GhosttyKit.xcframework` from the pinned
remux Ghostty source. It includes iOS arm64 device/simulator slices and exposes
the `ghostty_tmux_client_*` ABI used by the upstream controller. See
`ghosttykit-lock.json` and `scripts/verify-ghosttykit.sh` for the artifact
provenance and ABI checks.
