# Plan: MoriRemote iPad Support

## Overview

Add a real iPad experience to MoriRemote by introducing adaptive layouts for regular-width environments while preserving the current compact iPhone flow. The app already declares iPad in its target settings, so the work focuses on navigation, layout, and connection-state UX rather than platform enablement.

### Goals

- Provide a native-feeling iPad layout for disconnected and connected MoriRemote states.
- Preserve the current iPhone UX for compact-width devices, including iPad when shown in compact width.
- Make server selection, tmux navigation, terminal access, and connection management work smoothly in regular-width layouts.
- Keep implementation aligned with existing SwiftUI architecture and `ShellCoordinator` behavior.

### Success Criteria

- [ ] MoriRemote builds for iPad simulator without regressions to iPhone build.
- [ ] On regular-width environments, MoriRemote uses a two-column `NavigationSplitView` while disconnected/connecting and a persistent two-pane workspace while connected.
- [ ] On regular-width while disconnected, the detail pane shows placeholder/help or selected-server detail.
- [ ] On regular-width while connecting, the detail pane shows the target server, connection progress, and recoverable failure messaging.
- [ ] On regular-width while connected, the left pane shows server status + tmux navigation and the right pane shows terminal content.
- [ ] In compact width, including iPhone and compact-width iPad, MoriRemote keeps the current stacked navigation and overlay drawer behavior.
- [ ] Add/edit server flows remain usable from all entry points on both iPhone and iPad, with sensible sheet sizing on regular-width devices.
- [ ] No stale terminal chrome remains after switch host, disconnect, or failed connection recovery.

### Out of Scope

- Stage Manager or multi-window support.
- Major redesign of terminal rendering or tmux command semantics.
- Hardware-keyboard shortcut redesign beyond ensuring the existing UI still works.
- App Store metadata or screenshot work.
- Drag-and-drop or user-customizable multi-column arrangements.
- New automated UI-test infrastructure beyond any existing lightweight state/build coverage already present in the repo.

## Technical Approach

Adaptive rule:
- Regular-width behavior applies whenever the app is in a regular horizontal size class.
- Compact-width behavior applies whenever the app is in a compact horizontal size class, regardless of device idiom.
- This pass does not add special Stage Manager or multi-window handling beyond those size-class rules.

State model:
- **Disconnected browsing**: no active SSH session; regular-width UI may hold a selected server for browsing.
- **Connecting(targetServer)**: connection has been initiated for a specific server; `ShellCoordinator` records that server as the authoritative connection target immediately when connect starts.
- **Connected(activeServer)**: SSH is established and the app is transitioning into or already showing the terminal workspace for that server.
- **Shell(activeServer)**: terminal is open and tmux/sidebar interactions are active.
- **Connection failed(targetServer, error)**: connection attempt ended in failure; the disconnected regular-width detail should continue showing the same target server with failure messaging until the user retries, changes selection, edits the server, or starts another successful connection.

Ownership model:
- `ShellCoordinator.activeServer` becomes authoritative at connection initiation and remains the source of truth for the in-flight or active connection target.
- A lightweight regular-width UI selection tracks the currently browsed server while disconnected; it never owns the underlying SSH session.
- When a connection attempt fails, disconnected selection should remain on the same server where practical so the user can retry or edit without losing context.
- Failure UI must clear deterministically on reselection, retry, successful connection, or server edit.

Single-flight connection behavior:
- While in `Connecting(targetServer)`, MoriRemote treats connection as single-flight.
- A second connect action is disabled until the current attempt succeeds or fails.
- Changing disconnected selection during connection is allowed only as a browsing action and must not retarget the in-flight connection.
- `Switch Host` during an in-flight connection returns the UI to disconnected browsing and abandons the current attempt using existing coordinator disconnect/reset behavior.

On regular width:
- **Disconnected browsing / failed connection:** a `NavigationSplitView` with the server list in the sidebar and a detail pane that shows empty-state help or a selected-server summary with connect/retry/edit actions.
- **Connecting:** keep the same split structure, but the detail pane switches to a progress-focused state for `targetServer`, with failure messaging surfaced if connection fails.
- **Connected / shell:** a persistent workspace with one navigation pane containing server actions and tmux state, and one detail pane containing the terminal.

On compact width:
- Keep the current root-state switching behavior: server list before connection, terminal screen after connection.
- Keep the existing slide-over tmux drawer in `TerminalScreen`.
- Compact-width iPad follows the same behavior as iPhone.

Switch-host / disconnect behavior:
- **Disconnect** from the regular-width connected workspace tears down the active connection and returns immediately to the disconnected split view with the last browsed/active server still selected if possible.
- **Switch Host** from the regular-width connected workspace is treated as “leave current terminal and return to the disconnected split view,” reusing the selected server detail model so the user can choose another server without stale terminal UI remaining visible.
- This pass will not add a confirmation dialog unless existing behavior already requires one; it preserves current semantics while improving presentation.

Runtime size changes:
- Switching between regular and compact layouts must not drop the active SSH/tmux connection.
- If an active server is connected, layout changes only affect presentation; the same connection remains active.
- Presentation-specific UI state (for example phone drawer open/closed, selected split-view column visibility, transient sheet placement) may reset when crossing layout classes.
- Recreating the terminal container view during layout changes is acceptable as long as the underlying session remains active and renderer wiring/focus are restored correctly.

### Components

- **Adaptive root view**: Decides whether to render compact phone navigation or regular-width split/workspace navigation.
- **Regular-width selection model**: Stores disconnected split-view server selection without duplicating connection authority.
- **Stable terminal/session host**: Keeps shell lifecycle and renderer wiring centralized so root-layout changes do not imply session loss.
- **Reusable server list content**: Extract current server list UI so it can be embedded in both a phone `NavigationStack` and an iPad split view.
- **Disconnected detail content**: Regular-width detail views for empty, selected, connecting, and failure states.
- **Connected iPad workspace**: A regular-width container with a persistent tmux/server navigation pane and terminal detail pane.
- **Sidebar presentation adapters**: Reuse tmux sidebar content while making dismiss controls conditional on overlay vs persistent presentation.
- **Presentation polish**: Tune sheet sizing, placeholder copy, and sizing behavior for iPad readability.

## Implementation Phases

### Phase 1: Adaptive navigation and state foundation

1. Extract reusable server list content from `MoriRemote/MoriRemote/Views/ServerListView.swift` so it can be embedded in both compact and regular-width containers.
2. Introduce a lightweight regular-width disconnected selection model under `MoriRemote/MoriRemote/Views/` and update `MoriRemote/MoriRemote/MoriRemoteApp.swift` so regular width uses `NavigationSplitView` for disconnected/connecting states while compact width preserves the current root switching flow.
3. Establish a stable terminal/session host boundary early, so later regular-width workspace and runtime size-class transitions reuse the same shell lifecycle rules instead of coupling session continuity to a single presentation view.
4. Add regular-width detail content that covers: no servers yet, selected-server summary with connect action, connecting progress, and connection failure messaging with deterministic clearing rules.
5. Ensure runtime transitions between compact and regular width preserve connection state and keep disconnected selection resilient to split-view collapse/expansion.

### Phase 2: Connected iPad workspace

1. Refactor `MoriRemote/MoriRemote/Views/TerminalScreen.swift` so shell lifecycle/rendering stays centralized while presentation adapts between compact drawer mode and regular-width persistent-sidebar mode.
2. Reuse/adapt tmux navigation from `MoriRemote/MoriRemote/Views/TmuxSidebarView.swift` and related sidebar components so the regular-width connected workspace uses a persistent left pane containing server actions, tmux sessions/windows, switch-host, and disconnect controls.
3. Update sidebar/header components that currently assume dismiss-only overlay behavior, making close buttons and callbacks conditional for persistent iPad presentation.
4. Define connected-state transition behavior after disconnect, switch host, or interrupted in-flight connection so the UI returns cleanly to the regular-width disconnected split view without stale terminal chrome, while preserving the selected server where appropriate.

### Phase 3: iPad polish, docs, and verification

1. Adjust `MoriRemote/MoriRemote/Views/ServerFormView.swift` sheet sizing/presentation for regular-width iPad while preserving compact presentation.
2. Verify and adapt add/edit server invocation, save, dismiss, and list refresh behavior from both disconnected regular-width split view and compact flow.
3. Add/update localized strings in `MoriRemote/MoriRemote/Resources/en.lproj/Localizable.strings` and `MoriRemote/MoriRemote/Resources/zh-Hans.lproj/Localizable.strings` for any new placeholder/help/error copy.
4. Update `CHANGELOG.md` and, if platform support or usage description changes materially, `README.md` to reflect improved iPad support.
5. Run MoriRemote build verification on both an iPad simulator and an iPhone simulator, then fix any build/layout issues surfaced by compilation.
6. If there are existing lightweight state/build tests relevant to MoriRemote, update them; otherwise explicitly treat this change as manual-verification-only due to current test infrastructure.

## Testing Strategy

- Build MoriRemote for an iPad simulator destination.
- Build MoriRemote for an iPhone simulator destination to catch compact-layout regressions.
- Manually verify disconnected regular-width iPad state: empty state, populated server list, selected-server detail, add/edit sheet presentation.
- Manually verify connecting regular-width iPad state: selected target server shown, progress visible, failures surface cleanly, second connect is blocked, selection changes do not retarget the in-flight attempt, and retry/return flows work.
- Manually verify connected regular-width iPad state: terminal visible, persistent tmux/server pane visible, switch-host/disconnect flows accessible, and UI returns to disconnected split view after disconnect.
- Manually verify compact iPhone / compact-width iPad state still uses overlay sidebar and can connect/disconnect.
- Explicitly verify live size-class transitions: connected while rotating iPad, disconnecting after transition, starting a connection in compact and finishing in regular, starting in regular and collapsing to compact, and any presented sheet/drawer during transition.
- Explicitly verify terminal focus and input behavior after layout changes: software keyboard activation, accessory bar visibility, and tmux interaction still function.
- Sanity-check hardware keyboard behavior to ensure the persistent iPad sidebar does not break existing key input flow.
- Verify server-list mutation edge cases: editing the selected disconnected server, editing the currently connected server, deleting the selected server while disconnected, and deleting the previously active server after disconnect/switch-host.
- Verify failure-state lifetime: error copy clears on reselection, retry, successful connection, and server edit, and never appears for the wrong server.

## Risks

| Risk | Impact | Mitigation |
| ---- | ------ | ---------- |
| Root-view refactor could break current iPhone navigation | High | Keep compact path close to existing `ServerListView`/`TerminalScreen` behavior and build for iPhone simulator after each phase |
| Persistent iPad sidebar may conflict with terminal focus/keyboard behavior | High | Limit shell lifecycle changes; keep renderer setup in one place and only change presentation layer |
| Existing sidebar components may assume overlay dismissal affordances | Medium | Isolate persistent-vs-overlay behavior behind small view adapters and conditional controls |
| Selection/state handling could drift across connected/disconnected or compact/regular transitions | High | Keep connection authority in `ShellCoordinator`, keep disconnected browsing selection lightweight and presentation-agnostic, and manually verify rotation/size-class transitions |
| `NavigationSplitView` collapse/visibility behavior may vary across iPad sizes/orientations | Medium | Keep selected-server/detail state independent of split-view presentation so collapsing columns does not lose the current intent |
| Failure state could stick to the wrong server after retries or edits | Medium | Tie failure UI to the target server and clear it deterministically on reselection, retry, success, or edit |
| New iPad placeholder and guidance copy could miss localization/documentation requirements | Medium | Route new strings through localization files and update user-facing docs noted in repo guidance |

## Open Questions

- [x] Use a regular-width split view while disconnected and a persistent two-pane workspace while connected.
- [x] Preserve compact-width iPhone behavior as the baseline, including compact-width iPad.
- [x] Preserve the underlying SSH/tmux connection across layout changes even if presentation state resets.
- [x] Treat switch-host as a transition back to disconnected browsing rather than an in-place multi-host workflow.
- [x] Treat connection attempts as single-flight and keep `activeServer` authoritative from connect initiation.

## Review Feedback

### Round 1
- Clarified the exact regular-width information architecture for disconnected and connected states.
- Added explicit behavior for compact-width iPad and runtime size-class transitions.
- Expanded testing around terminal focus/input and connected-state flows.
- Added README/doc sync and selection/state regression coverage.

### Round 2
- Added an explicit regular-width disconnected selection model and split-view collapse mitigation.
- Defined connecting-state detail behavior and switch-host/disconnect transitions.
- Expanded add/edit workflow coverage and live size-class transition tests.
- Clarified terminal recreation vs underlying session preservation during layout changes.

### Round 3
- Added an explicit state model for connecting/failed states and failure clearing rules.
- Defined single-flight connection behavior and in-flight switch-host handling.
- Moved stable terminal/session-host extraction into Phase 1 because layout continuity depends on it.
- Added mutation/failure-lifetime verification and clarified the adaptive size-class rule.

## Final Status

Completed. MoriRemote now has an adaptive iPad experience with a regular-width split browser while disconnected, a persistent two-pane connected workspace, iPad-tuned server form presentation, localized new UI copy, and verified iPad/iPhone simulator builds. Remaining follow-up is optional cleanup only; no implementation-phase blockers remain.
