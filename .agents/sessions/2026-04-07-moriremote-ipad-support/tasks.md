# Tasks: MoriRemote iPad Support

## Phase 1: Adaptive navigation and state foundation
- [x] 1.1 Extract reusable server list content from `MoriRemote/MoriRemote/Views/ServerListView.swift`
- [x] 1.2 Add a regular-width disconnected selection model and adaptive root view in `MoriRemote/MoriRemote/MoriRemoteApp.swift` / new `Views/*`
- [x] 1.3 Establish a stable terminal/session host boundary for layout changes
- [x] 1.4 Add regular-width detail content for empty/selected/connecting/failure states
- [x] 1.5 Preserve connection state across compact/regular transitions and keep selection resilient to split-view collapse

## Phase 2: Connected iPad workspace
- [x] 2.1 Refactor `MoriRemote/MoriRemote/Views/TerminalScreen.swift` for compact drawer vs regular persistent-sidebar presentation
- [x] 2.2 Adapt `TmuxSidebarView` and related sidebar components for regular-width persistent navigation
- [x] 2.3 Update dismiss-only sidebar/header assumptions for persistent iPad presentation
- [x] 2.4 Return cleanly to disconnected split view after disconnect / switch host / interrupted connect

## Phase 3: iPad polish, docs, and verification
- [x] 3.1 Adjust `MoriRemote/MoriRemote/Views/ServerFormView.swift` iPad sheet sizing/presentation
- [x] 3.2 Verify/fix add-edit invocation, save, dismiss, and list refresh in compact + regular flows
- [x] 3.3 Add/update localization for any new MoriRemote strings
- [x] 3.4 Update `CHANGELOG.md` and `README.md` if needed
- [x] 3.5 Build MoriRemote for iPad + iPhone simulators and fix issues
- [x] 3.6 Update any existing lightweight tests if applicable, otherwise document manual-only verification
