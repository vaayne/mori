# Mori CLI

The `mori` CLI communicates with the running Mori app over a Unix socket
(`~/Library/Application Support/Mori/mori.sock`). It can manage projects,
worktrees, windows, and panes, and enables inter-agent communication through
context-aware addressing.

## Installation

**Homebrew** — the CLI is included automatically when you install Mori via `brew`.

**DMG** — after dragging Mori.app to Applications, launch the app and choose
**Mori > Install CLI...** from the menu bar. This symlinks the `mori` binary
into your PATH.

## Prerequisites

The CLI communicates with Mori.app via a Unix socket. If the app is not running,
the CLI **automatically launches it** and waits for the socket to become ready
(up to 10 seconds).

## Context-Aware Addressing

Every address component — `--project`, `--worktree`, `--window`, `--pane` — is
an optional flag. When omitted, the CLI falls back to the matching `MORI_*`
environment variable that Mori sets in every managed pane.

```
--project  →  MORI_PROJECT  →  required (error if missing)
--worktree →  MORI_WORKTREE →  required (error if missing)
--window   →  MORI_WINDOW   →  required (error if missing)
--pane     →  MORI_PANE_ID  →  optional (nil = active pane)
```

Inside a Mori terminal, most commands reduce to their bare form:

```bash
mori pane send "npm test Enter"   # all context from env vars
mori pane list                    # scopes to current window
mori window new --name logs       # uses current project/worktree
```

Outside a Mori terminal, pass flags explicitly:

```bash
mori pane send --project myapp --worktree main --window shell "npm test Enter"
```

## Environment Variables

Mori injects these into every managed pane:

| Variable | Description | Example |
|----------|-------------|---------|
| `MORI_PROJECT` | Project name | `myapp` |
| `MORI_WORKTREE` | Worktree name | `main` |
| `MORI_WINDOW` | Window (tab) name | `shell` |
| `MORI_PANE_ID` | tmux pane ID | `%42` |

---

## Command Reference

### `mori project list`

List all projects known to Mori.

```bash
mori project list
mori project list --json
```

### `mori project open PATH`

Open a project from a filesystem path. Creates it if not already tracked.

```bash
mori open .
mori open ~/workspace/myapp
```

---

### `mori worktree list`

List worktrees for a project.

```bash
mori worktree list                       # uses MORI_PROJECT
mori worktree list --project myapp
```

### `mori worktree new BRANCH`

Create a new git worktree and tmux session.

```bash
mori worktree new feat/auth              # uses MORI_PROJECT
mori worktree new feat/auth --project myapp
```

### `mori worktree delete`

Delete a worktree: kills its tmux session and removes the git worktree.
The main worktree cannot be deleted.

```bash
mori worktree delete                     # uses MORI_PROJECT + MORI_WORKTREE
mori worktree delete --project myapp --worktree feat/auth
```

---

### `mori window list`

List tmux windows in a worktree.

```bash
mori window list                         # uses MORI_PROJECT + MORI_WORKTREE
mori window list --project myapp --worktree main
```

### `mori window new`

Create a new tmux window (tab) in a worktree's session.

```bash
mori window new --name logs              # uses MORI_PROJECT + MORI_WORKTREE
mori window new --project myapp --worktree main --name tests
```

### `mori window rename NEWNAME`

Rename a window.

```bash
mori window rename terminal              # uses MORI_WINDOW (and project/worktree)
mori window rename terminal --window shell
```

### `mori window close`

Close (kill) a window.

```bash
mori window close                        # uses MORI_WINDOW
mori window close --window logs
```

---

### `mori pane list`

List panes. Inside a Mori terminal, scopes to the current window by default.
No env vars and no flags shows all panes across all projects.

```bash
mori pane list                           # current window (from env vars)
mori pane list --project myapp --worktree main --window shell
mori pane list --json
```

### `mori pane new`

Split a new pane in a window.

```bash
mori pane new                            # horizontal split in current window
mori pane new --split v --name agent
mori pane new --project myapp --worktree main --window shell
```

| Option | Description |
|--------|-------------|
| `--split h\|v` | Split direction: `h` horizontal (default), `v` vertical |
| `--name NAME` | Pane title |

### `mori pane send KEYS`

Send keystrokes to a pane. Keys use `tmux send-keys` syntax.

```bash
mori pane send "npm test Enter"          # active pane, current window
mori pane send --window logs "q"         # different window (pane auto-cleared)
mori pane send --pane %5 "C-c"          # specific pane by ID
```

> **Note:** When `--window` is overridden, `MORI_PANE_ID` is not inherited —
> the command targets the active pane of the specified window.

### `mori pane read`

Capture recent terminal output from a pane without switching to it.

```bash
mori pane read                           # active pane, 50 lines
mori pane read --lines 200
mori pane read --pane %4 --lines 100
```

| Option | Description |
|--------|-------------|
| `--lines N` | Lines to capture (1–200, default: 50) |
| `--pane ID` | tmux pane ID (default: active pane) |

### `mori pane rename NEWNAME`

Set a pane's title.

```bash
mori pane rename agent                   # uses MORI_PANE_ID
mori pane rename agent --pane %3
```

### `mori pane close`

Close (kill) a pane.

```bash
mori pane close                          # active pane
mori pane close --pane %3
```

### `mori pane message TEXT`

Send a message to another pane with automatic sender attribution.
The sender's identity is read from the caller's `MORI_*` env vars.

```bash
mori pane message "build done"           # targets current window
mori pane message "review ready" --window orchestrator
mori pane message "done" --project myapp --worktree main --window editor
```

### `mori pane id`

Print the current pane's identity. Local only — does not require Mori.app.

```bash
mori pane id
# myapp/main/shell pane:%42
```

---

### `mori focus`

Focus a project, worktree, or specific window in the Mori UI.

```bash
mori focus --project myapp                          # focus project
mori focus --project myapp --worktree feat/auth     # focus worktree
mori focus --window logs                            # focus window (context-aware)
mori focus --project myapp --worktree main --window logs
```

---

## Agent Integration

The pane commands enable inter-agent communication. A coding agent running in
one pane can discover, observe, and control other panes without leaving its
own terminal.

### Discovering other panes

```bash
# List all panes in the current worktree
mori pane list --worktree main

# Read the last 100 lines from the "tests" window
mori pane read --window tests --lines 100

# Read a specific pane
mori pane read --pane %5 --lines 50
```

### Sending commands to other panes

```bash
# Run tests in another window
mori pane send --window tests "mise run test Enter"

# Interrupt a running process in a specific pane
mori pane send --pane %3 "C-c"
```

### Splitting panes for parallel work

```bash
# Open a vertical split for a watching process
mori pane new --split v --name watcher

# Get the new pane's ID
mori pane list --json | jq '.[-1].tmuxPaneId'
```

### Messaging between agents

When multiple agents run in different panes, they can exchange messages with
full sender attribution:

```bash
# Agent in "shell" sends to "orchestrator"
mori pane message "subtask complete" --window orchestrator
```

The receiving pane sees the message formatted with the sender's
project/worktree/window/pane identity, all populated automatically from
the sender's `MORI_*` environment variables.

### Minimal automation example (inside Mori terminal)

```bash
#!/usr/bin/env bash
# Run tests and report result to orchestrator

mori pane send --window tests "mise run test Enter"
sleep 5
output=$(mori pane read --window tests --lines 20)

if echo "$output" | grep -q "passed"; then
    mori pane message "tests passed" --window orchestrator
else
    mori pane message "tests FAILED" --window orchestrator
fi
```
