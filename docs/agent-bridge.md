# Agent Bridge

Cross-pane agent monitoring, communication, and dashboard for Mori.

## Overview

The Agent Bridge lets agents running in different tmux panes discover each other, read output, and exchange messages. It builds on Mori's existing agent detection (process name, state heuristics) and adds structured communication primitives.

## CLI Commands

### `mori pane list`

List all panes across all projects/worktrees with their current state:

```bash
$ mori pane list
[
  {
    "endpoint": "local",
    "tmuxPaneId": "%5",
    "projectName": "mori",
    "worktreeName": "main",
    "windowName": "claude",
    "agentState": "running",
    "detectedAgent": "claude"
  },
  ...
]
```

### `mori pane read <project> <worktree> <window> [--lines N]`

Capture the last N lines (default: 50, max: 200) from a pane:

```bash
$ mori pane read mori main claude --lines 10
```

### `mori pane message <project> <worktree> <window> <text>`

Send a message to a pane with sender metadata envelope:

```bash
$ mori pane message mori main codex "Review the auth module changes"
```

This sends the following text to the target pane:

```
[mori-bridge from:mori/main/claude pane:%5] Review the auth module changes
```

### `mori pane id`

Print the current pane's identity (reads `MORI_*` environment variables):

```bash
$ mori pane id
mori/main/claude pane:%5
```

## Message Envelope Format

Messages use a simple, grep-friendly envelope format:

```
[mori-bridge from:<project>/<worktree>/<window> pane:<id>] <text>
```

### Parsing

Agents can extract messages with a simple regex or string match:

```bash
# Bash: extract sender and message
if [[ "$line" =~ ^\[mori-bridge\ from:(.+)\ pane:(.+)\]\ (.+)$ ]]; then
  sender="${BASH_REMATCH[1]}"
  pane_id="${BASH_REMATCH[2]}"
  message="${BASH_REMATCH[3]}"
fi
```

## Target Resolution

CLI commands accept `<project> <worktree> <window>` as target coordinates:

1. Project is matched by name (case-insensitive)
2. Worktree is matched within the project (case-insensitive)
3. Window is matched by title within the worktree (case-insensitive)
4. The active pane in the matched window is targeted (`activePaneId`)
5. For multi-pane windows, the active pane receives the command
6. SSH/remote worktrees use their own TmuxBackend instance

## UI Features

### Hover Peek

Hover any window row with an agent badge to see the last 8 lines of pane output in a popover. The popover appears after a 300ms delay and uses a 5-second cache to avoid excessive tmux queries.

### Quick Reply

Click a "waiting" badge on any window row to reveal an inline text field. Type a reply and press Enter — the text is sent as keys to the pane (with a newline appended).

### Agents Sidebar

The sidebar has three modes: Tasks, Workspaces, and Agents. The Agents mode shows all windows with detected agents, grouped by state:

- **Attention** — waiting for input or errored
- **Running** — actively executing
- **Completed** — finished successfully
- **Idle** — agent detected but no active state

### Agent Dashboard

Press ⌘⇧A to toggle a floating dashboard panel showing live output from all agent panes. The dashboard auto-refreshes every 5 seconds and pauses when hidden.

## Agent Skill Example

To enable an agent to use the bridge, add to its skill/instructions:

```
You can communicate with other agents via the mori CLI:
- List all panes: mori pane list
- Read output: mori pane read <project> <worktree> <window> --lines 50
- Send message: mori pane message <project> <worktree> <window> "your message"
- Check identity: mori pane id
```
