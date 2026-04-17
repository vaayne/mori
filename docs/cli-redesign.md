# CLI Redesign — Context-Aware Addressing

## Problem

Every command that targets a resource repeats `PROJECT WORKTREE WINDOW` as positional
arguments. This creates three concrete issues:

1. **Verbose scripts** — agent automations repeat the same address on every call.
2. **Missing resource operations** — no `worktree list`, no pane splits, no renames.
3. **Window/pane conflation** — `send` and `read` target the *active pane of a window*
   with no way to address a specific pane.

## Solution: Context-Aware Addressing

Mori terminals already export `MORI_PROJECT`, `MORI_WORKTREE`, `MORI_WINDOW`, and
`MORI_PANE_ID`. The redesign makes every address component an **optional flag** that
defaults to the matching env var when omitted.

### Resolution Priority (per component)

```
--project flag  >  MORI_PROJECT env var  >  error
--worktree flag >  MORI_WORKTREE env var >  error
--window flag   >  MORI_WINDOW env var   >  error
--pane flag     >  MORI_PANE_ID env var  >  (none — pane is optional in most commands)
```

### Before / After

```bash
# Outside Mori terminal — fully explicit
mori pane send --project myapp --worktree main --window shell "npm test Enter"
mori pane read --project myapp --worktree main --window shell --lines 100

# Inside a Mori terminal — use current context
mori pane send "npm test Enter"
mori pane read --lines 100

# Inside a Mori terminal — partial override (same project, different window)
mori pane send --window logs "q"
mori pane send --worktree feat/auth --window shell "git status Enter"
```

---

## New Command Tree

```
mori
├── project
│   ├── list
│   └── open PATH
│
├── worktree
│   ├── list   [--project P]
│   ├── new    BRANCH [--project P]
│   └── delete [--project P] [--worktree W]
│
├── window
│   ├── list   [--project P] [--worktree W]
│   ├── new    [--project P] [--worktree W] [--name NAME]
│   ├── rename NEWNAME [--project P] [--worktree W] [--window W]
│   └── close  [--project P] [--worktree W] [--window W]
│
├── pane
│   ├── list    [--project P] [--worktree W] [--window W]
│   ├── new     [--project P] [--worktree W] [--window W] [--split h|v] [--name NAME]
│   ├── send    KEYS [--project P] [--worktree W] [--window W] [--pane ID]
│   ├── read    [--project P] [--worktree W] [--window W] [--pane ID] [--lines N]
│   ├── rename  NEWNAME [--project P] [--worktree W] [--window W] [--pane ID]
│   ├── close   [--project P] [--worktree W] [--window W] [--pane ID]
│   ├── message TEXT [--project P] [--worktree W] [--window W]
│   └── id
│
├── focus  [--project P] [--worktree W] [--window W]
└── open   PATH
```

---

## Command Reference

### `mori project`

| Command | Description |
|---|---|
| `project list` | List all tracked projects |
| `project open PATH` | Register + open project from directory (`.` supported) |

### `mori worktree`

| Command | Description |
|---|---|
| `worktree list` | List all worktrees for a project |
| `worktree new BRANCH` | Create git worktree + tmux session |
| `worktree delete` | Delete worktree and its tmux session |

**`worktree list`**
```
Flags:
  --project   Project name  [env: MORI_PROJECT]
  --json      Machine-readable output

Output (human):
  Name        Branch          Path
  ──────────  ──────────────  ──────────────────────────
  main        main            ~/workspace/myapp
  feat/auth   feat/auth       ~/workspace/myapp-feat-auth

Output (JSON):
  [{"name":"main","branch":"main","path":"..."},...]
```

**`worktree new BRANCH`**
```
Arguments:
  BRANCH      Branch name (new or existing)

Flags:
  --project   Project name  [env: MORI_PROJECT]
  --json

Output:
  ✓ Created worktree 'feat/auth' on branch 'feat/auth' at ~/workspace/myapp-feat-auth
```

**`worktree delete`**
```
Flags:
  --project   Project name    [env: MORI_PROJECT]
  --worktree  Worktree name   [env: MORI_WORKTREE]
  --force     Skip confirmation (for scripts)
  --json

Behavior:
  - Confirms interactively unless --force
  - Kills tmux session, removes git worktree
  - Errors if worktree is currently focused in the UI
```

### `mori window`

| Command | Description |
|---|---|
| `window list` | List all windows in a worktree |
| `window new` | Create a new tmux window (tab) |
| `window rename NEWNAME` | Rename a window |
| `window close` | Close a window |

**`window list`**
```
Flags:
  --project   [env: MORI_PROJECT]
  --worktree  [env: MORI_WORKTREE]
  --json

Output (human):
  Name    Active  Panes
  ──────  ──────  ─────
  shell   yes     2
  logs    no      1
  tests   no      1
```

**`window new`**
```
Flags:
  --project   [env: MORI_PROJECT]
  --worktree  [env: MORI_WORKTREE]
  --name      Window name (default: shell)
  --json
```

**`window rename NEWNAME`**
```
Arguments:
  NEWNAME     New window name

Flags:
  --project   [env: MORI_PROJECT]
  --worktree  [env: MORI_WORKTREE]
  --window    Current window name  [env: MORI_WINDOW]
  --json
```

**`window close`**
```
Flags:
  --project   [env: MORI_PROJECT]
  --worktree  [env: MORI_WORKTREE]
  --window    [env: MORI_WINDOW]
  --force     Skip confirmation
  --json
```

### `mori pane`

| Command | Description |
|---|---|
| `pane list` | List panes with agent state |
| `pane new` | Split active window into a new pane |
| `pane send KEYS` | Send tmux keys to a pane |
| `pane read` | Capture pane output |
| `pane rename NEWNAME` | Rename a pane |
| `pane close` | Close a pane |
| `pane message TEXT` | Send inter-agent message |
| `pane id` | Print current pane identity |

**`pane list`**
```
Flags:
  --project   [env: MORI_PROJECT]    (optional filter)
  --worktree  [env: MORI_WORKTREE]   (optional filter)
  --window    [env: MORI_WINDOW]     (optional filter — NEW)
  --json

Output (human):
  Project  Worktree   Window  Pane    Agent    State
  ───────  ─────────  ──────  ──────  ───────  ──────────
  myapp    main       shell   %3      claude   ⚡ running
  myapp    main       logs    %4      –        –
```

**`pane new`**
```
Flags:
  --project   [env: MORI_PROJECT]
  --worktree  [env: MORI_WORKTREE]
  --window    [env: MORI_WINDOW]
  --split     Split direction: h (horizontal) | v (vertical)  [default: h]
  --name      Pane title
  --json

Output (JSON):
  {"paneId":"%5","window":"shell"}
```

**`pane send KEYS`**
```
Arguments:
  KEYS        tmux send-keys syntax (e.g. "npm test Enter", "C-c")

Flags:
  --project   [env: MORI_PROJECT]
  --worktree  [env: MORI_WORKTREE]
  --window    [env: MORI_WINDOW]
  --pane      tmux pane ID (e.g. %3)  [env: MORI_PANE_ID]
              If omitted: targets the active pane of the window
  --json

Examples:
  mori pane send "npm test Enter"            # context from env vars
  mori pane send --window logs "q"           # different window, same project/worktree
  mori pane send --pane %5 "C-c"            # specific pane
```

**`pane read`**
```
Flags:
  --project   [env: MORI_PROJECT]
  --worktree  [env: MORI_WORKTREE]
  --window    [env: MORI_WINDOW]
  --pane      tmux pane ID  [env: MORI_PANE_ID]
              If omitted: active pane of the window
  --lines     Lines to capture (1–200, default: 50)
  --json      Wraps output in {"output":"..."}

Examples:
  mori pane read                     # read current pane (50 lines)
  mori pane read --lines 200         # read more
  mori pane read --pane %4           # read a specific pane
```

**`pane rename NEWNAME`**
```
Arguments:
  NEWNAME     New pane title

Flags:
  --project   [env: MORI_PROJECT]
  --worktree  [env: MORI_WORKTREE]
  --window    [env: MORI_WINDOW]
  --pane      tmux pane ID  [env: MORI_PANE_ID]
  --json
```

**`pane close`**
```
Flags:
  --project   [env: MORI_PROJECT]
  --worktree  [env: MORI_WORKTREE]
  --window    [env: MORI_WINDOW]
  --pane      tmux pane ID  [env: MORI_PANE_ID]
  --force     Skip confirmation
  --json
```

**`pane message TEXT`**
```
Arguments:
  TEXT        Message body

Flags:
  --project   Target project   [env: MORI_PROJECT as sender default]
  --worktree  Target worktree  [env: MORI_WORKTREE as sender default]
  --window    Target window    [env: MORI_WINDOW as sender default]
  --json

Note: Sender identity always comes from MORI_* env vars automatically.
```

**`pane id`**
```
No flags. Reads MORI_* env vars. Does not require Mori.app.

Output:
  myapp/main/shell pane:%3
```

### `mori focus`

```
Flags:
  --project   [env: MORI_PROJECT]
  --worktree  [env: MORI_WORKTREE]  (optional — focuses project only if omitted)
  --window    [env: MORI_WINDOW]    (optional — focuses worktree only if omitted)
  --json

Examples:
  mori focus --project myapp                       # focus project
  mori focus --project myapp --worktree feat/auth  # focus worktree
  mori focus --window logs                          # focus window (context-aware)
```

---

## New IPC Commands Required

The following cases must be added to `IPCCommand` in `MoriIPC/IPCProtocol.swift`:

```swift
// Worktree
case worktreeList(project: String)
case worktreeDelete(project: String, worktree: String)

// Window
case windowList(project: String, worktree: String)
case windowRename(project: String, worktree: String, window: String, newName: String)
case windowClose(project: String, worktree: String, window: String)

// Pane
case paneNew(project: String, worktree: String, window: String,
             split: String?, name: String?)            // split: "h" | "v" | nil
case paneSend(project: String, worktree: String, window: String,
              pane: String?, keys: String)              // pane: tmux pane ID or nil
case paneRename(project: String, worktree: String, window: String,
                pane: String, newName: String)
case paneClose(project: String, worktree: String, window: String,
               pane: String?)                          // nil = active pane

// Focus (extend existing to accept optional worktree/window)
case focusWindow(project: String, worktree: String, window: String)
```

Existing commands kept as-is (app-side handlers unchanged):
- `.projectList` → unchanged
- `.worktreeCreate` → kept, new `.worktreeNew` is an alias at CLI layer only
- `.focus` → unchanged (project + worktree only)
- `.send` → **deprecated**, replaced by `.paneSend`
- `.newWindow` → **deprecated**, replaced by `.windowNew` at CLI layer mapping to existing handler
- `.open` → unchanged
- `.paneList` → gains optional `window` filter parameter
- `.paneRead` → gains optional `pane` parameter
- `.paneMessage` → unchanged

---

## Migration / Breaking Changes

### Deprecated commands (print warning, still work)

| Old | New |
|---|---|
| `mori send PROJECT WORKTREE WINDOW KEYS` | `mori pane send --project P --worktree W --window W KEYS` |
| `mori new-window PROJECT WORKTREE` | `mori window new --project P --worktree W` |
| `mori worktree create PROJECT BRANCH` | `mori worktree new BRANCH --project P` |
| `mori focus PROJECT WORKTREE` | `mori focus --project P --worktree W` |

Deprecated commands print to stderr:
```
⚠ 'mori send' is deprecated. Use 'mori pane send' instead.
```

### Changed behavior

- `pane list --project` / `--worktree` remain optional filters (no breaking change)
- `pane list` gains `--window` filter (additive, no breaking change)
- `pane read` and `pane send` gain `--pane` flag (additive, no breaking change)
- All address arguments change from **positional** to **flags** in the new commands

---

## Implementation Order

1. **IPC layer** — Add new `IPCCommand` cases to `MoriIPC/IPCProtocol.swift`
2. **App handler** — Add new handlers in `IPCHandler.swift`
   - `worktreeList`, `worktreeDelete`
   - `windowList`, `windowRename`, `windowClose`
   - `paneNew`, `paneSend` (pane-targeted), `paneRename`, `paneClose`
3. **CLI layer** — Rewrite command structs in `MoriCLI.swift`
   - New `Window` command group
   - New subcommands under `Worktree`, `Pane`
   - Replace positional args with flags + env-var defaults
   - Wrap old positional commands as deprecated aliases
4. **Output formatters** — Add `formatWorktreeList`, `formatWindowList`
5. **Localization** — Add all new user-facing strings to `en.lproj` and `zh-Hans.lproj`

---

## Shared Address Resolution Helper

All commands should resolve addresses through a single helper to avoid duplication:

```swift
/// Resolves an address component from an explicit flag or env var.
/// Throws a localized error if neither source provides a value.
func resolveAddress(
    flag: String?,
    envKey: String,
    label: String
) throws -> String {
    if let v = flag { return v }
    if let v = ProcessInfo.processInfo.environment[envKey] { return v }
    throw CLIError.missingAddress(label: label, envKey: envKey)
}

// Usage in a command:
let project  = try resolveAddress(flag: projectFlag,  envKey: "MORI_PROJECT",  label: "project")
let worktree = try resolveAddress(flag: worktreeFlag, envKey: "MORI_WORKTREE", label: "worktree")
let window   = try resolveAddress(flag: windowFlag,   envKey: "MORI_WINDOW",   label: "window")
// pane is optional — nil means "active pane of window"
let pane     = paneFlag ?? ProcessInfo.processInfo.environment["MORI_PANE_ID"]
```

Error message format:
```
Error: project not specified. Pass --project or set MORI_PROJECT.
```
