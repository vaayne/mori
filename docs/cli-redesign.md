# CLI Redesign — Context-Aware Addressing

## Problem

Every command that targets a resource repeats `PROJECT WORKTREE WINDOW` as positional
arguments. This creates four concrete issues:

1. **Verbose scripts** — agent automations repeat the same address on every call.
2. **Missing resource operations** — no `worktree list/delete`, no pane splits, no renames.
3. **Window/pane conflation** — `send` and `read` target the *active pane of a window*
   with no way to address a specific pane.
4. **No pane listing** — `pane list` exists but scopes vaguely via optional filters rather
   than being a first-class `pane list` that mirrors `window list`.

No backward compatibility is maintained. Old commands are removed.

## Solution: Context-Aware Addressing

Mori terminals already export `MORI_PROJECT`, `MORI_WORKTREE`, `MORI_WINDOW`, and
`MORI_PANE_ID`. The redesign makes every address component an **optional flag** that
defaults to the matching env var when omitted.

### Resolution Priority (per component)

```
--project flag  >  MORI_PROJECT env var  >  error
--worktree flag >  MORI_WORKTREE env var >  error
--window flag   >  MORI_WINDOW env var   >  error
--pane flag     >  MORI_PANE_ID env var  >  nil (pane is optional — means "active pane")
```

### Before / After

```bash
# Outside Mori terminal — fully explicit
mori pane send --project myapp --worktree main --window shell "npm test Enter"
mori pane list --project myapp --worktree main --window shell

# Inside a Mori terminal — zero ceremony
mori pane send "npm test Enter"
mori pane list                         # lists panes in current window

# Partial override — same project/worktree, different window
mori pane send --window logs "q"
mori pane list --window logs
```

---

## Command Tree

```
mori
├── project
│   ├── list
│   └── open PATH
│
├── worktree
│   ├── list   [--project P]
│   ├── new    BRANCH [--project P]
│   └── delete [--project P] [--worktree W] [--force]
│
├── window
│   ├── list   [--project P] [--worktree W]
│   ├── new    [--project P] [--worktree W] [--name NAME]
│   ├── rename NEWNAME [--project P] [--worktree W] [--window W]
│   └── close  [--project P] [--worktree W] [--window W] [--force]
│
├── pane
│   ├── list    [--project P] [--worktree W] [--window W]
│   ├── new     [--project P] [--worktree W] [--window W] [--split h|v] [--name NAME]
│   ├── send    KEYS [--project P] [--worktree W] [--window W] [--pane ID]
│   ├── read    [--project P] [--worktree W] [--window W] [--pane ID] [--lines N]
│   ├── rename  NEWNAME [--project P] [--worktree W] [--window W] [--pane ID]
│   ├── close   [--project P] [--worktree W] [--window W] [--pane ID] [--force]
│   ├── message TEXT [--project P] [--worktree W] [--window W]
│   └── id
│
├── focus  [--project P] [--worktree W] [--window W]
└── open   PATH
```

### Symmetry across resource levels

Each resource (worktree, window, pane) supports the same lifecycle verbs:

| Verb | worktree | window | pane |
|---|---|---|---|
| `list` | ✓ | ✓ | ✓ |
| `new` | ✓ (creates git worktree + tmux session) | ✓ (new tmux window) | ✓ (split) |
| `rename` | — | ✓ | ✓ |
| `close` / `delete` | `delete` | `close` | `close` |

Worktrees use `delete` (heavier — removes git worktree + session).
Windows and panes use `close` (lighter — kills the tmux entity).

---

## Command Reference

### `mori project`

**`project list`**
```
Flags: --json

Output:
  Name     Path
  ───────  ────────────────────────
  myapp    ~/workspace/myapp
  infra    ~/workspace/infra
```

**`project open PATH`**
```
Arguments:
  PATH   Directory path. Use '.' for current directory.

Flags: --json

Output:
  ✓ Opened project 'myapp' (~/workspace/myapp)
```

---

### `mori worktree`

**`worktree list`**
```
Flags:
  --project P   [env: MORI_PROJECT]
  --json

Output:
  Name        Branch          Path
  ──────────  ──────────────  ──────────────────────────────────
  main        main            ~/workspace/myapp
  feat/auth   feat/auth       ~/workspace/myapp-feat-auth
```

**`worktree new BRANCH`**
```
Arguments:
  BRANCH   Branch name (new or existing)

Flags:
  --project P   [env: MORI_PROJECT]
  --json

Output:
  ✓ Created worktree 'feat/auth' on branch 'feat/auth' at ~/workspace/myapp-feat-auth

JSON: {"name":"feat/auth","branch":"feat/auth","path":"..."}
```

**`worktree delete`**
```
Flags:
  --project P    [env: MORI_PROJECT]
  --worktree W   [env: MORI_WORKTREE]
  --force        Skip confirmation
  --json

Behavior:
  - Prompts for confirmation unless --force
  - Kills tmux session, removes git worktree directory
  - Errors if the worktree is currently focused in the UI

Output:
  ✓ Deleted worktree 'feat/auth'
```

---

### `mori window`

**`window list`**
```
Flags:
  --project P    [env: MORI_PROJECT]
  --worktree W   [env: MORI_WORKTREE]
  --json

Output:
  Name    Active  Panes
  ──────  ──────  ─────
  shell   yes     2
  logs    no      1
  tests   no      1
```

**`window new`**
```
Flags:
  --project P    [env: MORI_PROJECT]
  --worktree W   [env: MORI_WORKTREE]
  --name NAME    Window name (default: shell)
  --json

Output:
  ✓ Created window 'logs' in myapp/main
```

**`window rename NEWNAME`**
```
Arguments:
  NEWNAME   New window name

Flags:
  --project P    [env: MORI_PROJECT]
  --worktree W   [env: MORI_WORKTREE]
  --window W     [env: MORI_WINDOW]
  --json

Output:
  ✓ Renamed window 'shell' → 'terminal'
```

**`window close`**
```
Flags:
  --project P    [env: MORI_PROJECT]
  --worktree W   [env: MORI_WORKTREE]
  --window W     [env: MORI_WINDOW]
  --force        Skip confirmation
  --json

Output:
  ✓ Closed window 'logs'
```

---

### `mori pane`

`pane list` scopes to the current/specified window by default, matching the pattern of
`window list` scoping to the current worktree. Pass no `--window` to see all panes across
all windows (useful for the agent dashboard view).

**`pane list`**
```
Flags:
  --project P    [env: MORI_PROJECT]   (optional filter)
  --worktree W   [env: MORI_WORKTREE]  (optional filter)
  --window W     [env: MORI_WINDOW]    (optional filter)
  --json

Scoping behavior:
  - No flags in Mori terminal → shows panes in current window (from env vars)
  - --window → scopes to that window
  - No env vars, no flags → shows all panes (global view, like old behavior)

Output:
  Project  Worktree  Window  Pane  Title       Agent    State
  ───────  ────────  ──────  ────  ──────────  ───────  ──────────
  myapp    main      shell   %3    (claude)    claude   ⚡ running
  myapp    main      shell   %4    (vim)       –        –

JSON: [{"tmuxPaneId":"%3","projectName":"myapp","worktreeName":"main",
        "windowName":"shell","paneTitle":"claude","agentState":"running",
        "detectedAgent":"claude"},...]
```

**`pane new`**
```
Flags:
  --project P    [env: MORI_PROJECT]
  --worktree W   [env: MORI_WORKTREE]
  --window W     [env: MORI_WINDOW]
  --split h|v    Split direction: h = horizontal, v = vertical (default: h)
  --name NAME    Pane title
  --json

Output:
  ✓ Created pane %5 in myapp/main/shell

JSON: {"paneId":"%5","window":"shell"}
```

**`pane send KEYS`**
```
Arguments:
  KEYS   tmux send-keys syntax. Examples: "npm test Enter", "C-c", "q"

Flags:
  --project P    [env: MORI_PROJECT]
  --worktree W   [env: MORI_WORKTREE]
  --window W     [env: MORI_WINDOW]
  --pane ID      tmux pane ID, e.g. %3  [env: MORI_PANE_ID]
                 If omitted: active pane of the window
  --json

Examples:
  mori pane send "npm test Enter"           # current context
  mori pane send --window logs "q"          # different window
  mori pane send --pane %5 "C-c"           # specific pane
```

**`pane read`**
```
Flags:
  --project P    [env: MORI_PROJECT]
  --worktree W   [env: MORI_WORKTREE]
  --window W     [env: MORI_WINDOW]
  --pane ID      tmux pane ID  [env: MORI_PANE_ID]
                 If omitted: active pane of the window
  --lines N      Lines to capture (1–200, default: 50)
  --json         Wraps output in {"output":"..."}

Examples:
  mori pane read                   # current pane, 50 lines
  mori pane read --lines 200
  mori pane read --pane %4         # read a non-active pane
```

**`pane rename NEWNAME`**
```
Arguments:
  NEWNAME   New pane title

Flags:
  --project P    [env: MORI_PROJECT]
  --worktree W   [env: MORI_WORKTREE]
  --window W     [env: MORI_WINDOW]
  --pane ID      tmux pane ID  [env: MORI_PANE_ID]
  --json

Output:
  ✓ Renamed pane %3 → 'agent'
```

**`pane close`**
```
Flags:
  --project P    [env: MORI_PROJECT]
  --worktree W   [env: MORI_WORKTREE]
  --window W     [env: MORI_WINDOW]
  --pane ID      tmux pane ID  [env: MORI_PANE_ID]
                 If omitted: active pane of the window
  --force        Skip confirmation
  --json

Output:
  ✓ Closed pane %3
```

**`pane message TEXT`**
```
Arguments:
  TEXT   Message body

Flags:
  --project P    Target project   (default: MORI_PROJECT — used as *sender* when not overriding)
  --worktree W   Target worktree
  --window W     Target window
  --json

Note: Sender identity is always read from MORI_* env vars automatically.
```

**`pane id`**
```
No flags. Reads MORI_* env vars. Does not require Mori.app.

Output:
  myapp/main/shell pane:%3
```

---

### `mori focus`

```
Flags:
  --project P    [env: MORI_PROJECT]
  --worktree W   [env: MORI_WORKTREE]   optional
  --window W     [env: MORI_WINDOW]     optional
  --json

Behavior:
  - --project only       → focus the project (selects its last active worktree)
  - --project --worktree → focus the worktree
  - all three            → focus the specific window

Examples:
  mori focus --project myapp
  mori focus --project myapp --worktree feat/auth
  mori focus --window logs               # context-aware: same project/worktree
```

---

## New IPC Commands Required

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
             split: String?,   // "h" | "v" | nil (default h)
             name: String?)
case paneSend(project: String, worktree: String, window: String,
              pane: String?,   // tmux pane ID or nil = active pane
              keys: String)
case paneRename(project: String, worktree: String, window: String,
                pane: String, newName: String)
case paneClose(project: String, worktree: String, window: String,
               pane: String?)  // nil = active pane

// Focus — extend to optionally include window
case focusWindow(project: String, worktree: String, window: String)
```

Existing commands removed from `IPCCommand`:
- `.send` → replaced by `.paneSend`
- `.newWindow` → replaced by `.windowNew` (maps to new `windowList`/`windowClose` group)

Existing commands unchanged:
- `.projectList`, `.worktreeCreate`, `.focus`, `.open`
- `.paneList` — gains optional `window` parameter
- `.paneRead` — gains optional `pane` parameter
- `.paneMessage` — unchanged

---

## Shared Address Resolution

All commands resolve addresses through one helper to avoid duplication:

```swift
enum CLIError: Error {
    case missingAddress(label: String, envKey: String)
}

extension CLIError: CustomStringConvertible {
    var description: String {
        switch self {
        case .missingAddress(let label, let envKey):
            return "\(label) not specified. Pass --\(label) or set \(envKey)."
        }
    }
}

func resolveRequired(_ flag: String?, envKey: String, label: String) throws -> String {
    if let v = flag { return v }
    if let v = ProcessInfo.processInfo.environment[envKey] { return v }
    throw CLIError.missingAddress(label: label, envKey: envKey)
}

func resolveOptional(_ flag: String?, envKey: String) -> String? {
    flag ?? ProcessInfo.processInfo.environment[envKey]
}
```

Usage in every command's `run()`:
```swift
let project  = try resolveRequired(projectFlag,  envKey: "MORI_PROJECT",  label: "project")
let worktree = try resolveRequired(worktreeFlag, envKey: "MORI_WORKTREE", label: "worktree")
let window   = try resolveRequired(windowFlag,   envKey: "MORI_WINDOW",   label: "window")
let pane     = resolveOptional(paneFlag, envKey: "MORI_PANE_ID")  // nil = active pane
```

---

## Implementation Order

1. **IPC layer** — Add new `IPCCommand` cases; remove `.send` and `.newWindow`
2. **App handler** — `IPCHandler.swift`: add handlers for all new cases; remove old ones
3. **CLI layer** — Rewrite `MoriCLI.swift`: new `Window` group; convert all address args
   to flags with env-var defaults; remove deprecated top-level commands
4. **Output formatters** — Add `formatWorktreeList`, `formatWindowList`, `formatPaneNew`
5. **Localization** — New strings in `en.lproj` and `zh-Hans.lproj`
