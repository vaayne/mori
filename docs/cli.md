# Mori CLI

The `mori` CLI communicates with the running Mori app over a Unix socket
(`~/Library/Application Support/Mori/mori.sock`). It can list projects, create
worktrees, focus windows, send keystrokes, and facilitate inter-agent
communication through pane commands.

## Installation

**Homebrew** — the CLI is included automatically when you install Mori via `brew`.

**DMG** — after dragging Mori.app to Applications, launch the app and choose
**Mori > Install CLI...** from the menu bar. This symlinks the `mori` binary
into your PATH.

## Prerequisites

The Mori app must be running. If it is not, every command exits with:

```
Error: Mori app is not running. Launch Mori and try again.
```

If the socket file exists but the app is not accepting connections (stale socket
from a previous crash), the CLI prints:

```
Error: Mori app is not accepting CLI connections. Quit and relaunch Mori, then try again.
```

## Commands

### `mori project list`

List all projects known to Mori.

```bash
mori project list
```

Example output:

```json
[{"name":"dotfiles","path":"/Users/v/.dotfiles"},{"name":"mori","path":"/Users/v/workspace/mori"}]
```

### `mori worktree create`

Create a new worktree under an existing project.

```bash
mori worktree create <project> <branch>
```

| Argument | Description |
|----------|-------------|
| `project` | Project name |
| `branch` | Branch name for the new worktree |

```bash
mori worktree create mori feature/cli-docs
```

### `mori focus`

Focus (select) a specific project and worktree in the Mori UI.

```bash
mori focus <project> <worktree>
```

| Argument | Description |
|----------|-------------|
| `project` | Project name |
| `worktree` | Worktree name |

```bash
mori focus mori main
```

### `mori send`

Send keys to a specific tmux window. Keys are forwarded via `tmux send-keys`,
so tmux key names like `Enter`, `C-c`, and `Escape` are supported.

```bash
mori send <project> <worktree> <window> <keys>
```

| Argument | Description |
|----------|-------------|
| `project` | Project name |
| `worktree` | Worktree name |
| `window` | Window (tab) name |
| `keys` | Keys to send (tmux syntax) |

```bash
mori send mori main shell "echo hello Enter"
mori send mori main shell "C-c"
```

### `mori new-window`

Create a new window (tab) in a worktree's tmux session.

```bash
mori new-window <project> <worktree> [--name <name>]
```

| Argument / Option | Description |
|-------------------|-------------|
| `project` | Project name |
| `worktree` | Worktree name |
| `--name` | Optional window name (defaults to shell) |

```bash
mori new-window mori main --name logs
```

### `mori open`

Open a project from a filesystem path. If the path matches an existing project,
Mori focuses it. Otherwise Mori creates a new project from the directory.

```bash
mori open <path>
```

| Argument | Description |
|----------|-------------|
| `path` | Path to project directory |

```bash
mori open ~/workspace/mori
mori open .
```

### `mori status`

Set the workflow status for a worktree. Status is displayed as a badge in the
sidebar.

```bash
mori status <project> <worktree> <status>
```

| Argument | Description |
|----------|-------------|
| `project` | Project name |
| `worktree` | Worktree name |
| `status` | One of: `todo`, `inProgress`, `needsReview`, `done`, `cancelled` |

```bash
mori status mori feature/cli-docs inProgress
mori status mori feature/cli-docs done
```

### `mori pane list`

List all panes across projects and worktrees. Optionally filter by project
and/or worktree.

```bash
mori pane list [--project <name>] [--worktree <name>]
```

| Option | Description |
|--------|-------------|
| `--project` | Filter by project name |
| `--worktree` | Filter by worktree name |

```bash
mori pane list
mori pane list --project mori
mori pane list --project mori --worktree main
```

### `mori pane read`

Capture recent output from a pane. Useful for agents to inspect another pane's
terminal contents without switching to it.

```bash
mori pane read <project> <worktree> <window> [--lines <n>]
```

| Argument / Option | Description |
|-------------------|-------------|
| `project` | Project name |
| `worktree` | Worktree name |
| `window` | Window (tab) name |
| `--lines` | Number of lines to capture (default: 50, max: 200) |

```bash
mori pane read mori main shell
mori pane read mori main logs --lines 100
```

### `mori pane message`

Send a message to another pane with sender metadata. The sender's identity is
automatically read from environment variables (see below), so the receiving pane
knows who sent the message.

```bash
mori pane message <project> <worktree> <window> <text>
```

| Argument | Description |
|----------|-------------|
| `project` | Target project name |
| `worktree` | Target worktree name |
| `window` | Target window (tab) name |
| `text` | Message text |

```bash
mori pane message mori main shell "build completed successfully"
```

### `mori pane id`

Print the current pane's identity. This is a local-only command that reads
environment variables — it does not require the Mori app to be running.

```bash
mori pane id
```

Example output:

```
mori/main/shell pane:%42
```

## Environment Variables

Mori sets these environment variables in every tmux pane it manages. They
identify the pane's location within the project/worktree/window hierarchy.

| Variable | Description | Example |
|----------|-------------|---------|
| `MORI_PROJECT` | Project name | `mori` |
| `MORI_WORKTREE` | Worktree name | `main` |
| `MORI_WINDOW` | Window (tab) name | `shell` |
| `MORI_PANE_ID` | tmux pane ID | `%42` |

These variables are used automatically by `mori pane message` to attach sender
metadata, and by `mori pane id` to print the current identity.

## Agent Integration

The pane commands enable inter-agent communication within Mori. A coding agent
running in one pane can observe and interact with other panes without leaving
its own terminal.

### Discovering other panes

An agent can list all available panes, then read output from a specific one:

```bash
# List panes in the current project
mori pane list --project mori

# Read the last 50 lines from the "logs" tab
mori pane read mori main logs

# Read more history
mori pane read mori main logs --lines 200
```

### Sending commands to other panes

An agent can send keystrokes to run commands in another pane:

```bash
# Run a test suite in the "tests" tab
mori send mori main tests "mise run test Enter"

# Interrupt a running process
mori send mori main server "C-c"
```

### Messaging between agents

When multiple agents run in different panes, they can exchange messages with
sender attribution:

```bash
# Agent in "shell" pane sends a message to "editor" pane
mori pane message mori main editor "refactoring complete, please review"
```

The receiving pane sees the message along with metadata identifying the sender's
project, worktree, window, and pane ID — all populated automatically from the
sender's `MORI_*` environment variables.

### Setting workflow status

Agents can update the worktree's workflow status to signal progress:

```bash
mori status mori feature/auth inProgress   # working on it
mori status mori feature/auth needsReview  # ready for review
mori status mori feature/auth done         # finished
```
