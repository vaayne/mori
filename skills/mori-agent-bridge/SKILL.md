---
name: mori-agent-bridge
description: >
  Use Mori CLI to enable agent-to-agent communication and coordination across
  Mori-managed panes. Use this whenever you need to launch a helper agent, send
  a message to another agent (Claude, Pi, Codex), read another agent's output,
  or coordinate multi-agent workflows. Prefer this over ad-hoc tmux whenever
  the task involves mori pane operations or agent-to-agent messaging.
---

# Mori Agent Bridge

Three operations — discover, read, send. Always discover first.

## Golden rules

> **Stable IDs only.** Never address by window name — names churn when agents update terminal titles.
> Use `$MORI_PANE` (self), `$MORI_WINDOW` (current window), or resolve `tmuxPaneId` from `mori pane list`.

> **Same session/worktree only.** When creating a new pane or reusing an existing agent, it **must** be in the same tmux session and Mori worktree as the caller. Never spawn or target panes across different sessions or worktrees — scope all operations with `$MORI_SESSION`, `$MORI_PROJECT`, and `$MORI_WORKTREE`.

## Environment variables (set automatically in Mori panes)

| Variable       | Example     | Use                              |
| -------------- | ----------- | -------------------------------- |
| `MORI_PROJECT` | `mori`      | Scope CLI queries                |
| `MORI_WORKTREE`| `main`      | Scope CLI queries                |
| `MORI_SESSION` | `$1`        | tmux session addressing          |
| `MORI_WINDOW`  | `@3`        | Stable window ID for Mori CLI    |
| `MORI_PANE`    | `%42`       | Stable pane ID for tmux commands |

## 1. Discover panes

```bash
# Peers in the current worktree (use this by default)
mori pane list --json | jq --arg p "$MORI_PROJECT" --arg w "$MORI_WORKTREE" \
  '.[] | select(.projectName==$p and .worktreeName==$w)'

# Look up a specific pane
mori pane list --json | jq '.[] | select(.tmuxPaneId=="%56")'

# Current pane identity
echo "$MORI_PANE"   # or: mori pane id
```

Key fields in the JSON output:

| Field           | Reliable? | Notes                                              |
| --------------- | --------- | -------------------------------------------------- |
| `tmuxPaneId`    | Stable    | Primary handle for all operations                  |
| `projectName`   | Stable    | Set at pane creation                               |
| `worktreeName`  | Stable    | Set at pane creation                               |
| `windowName`    | Ephemeral | Changes when any pane updates its title — avoid    |
| `agentState`    | Live      | `running` / `waitingForInput` / `none`             |
| `paneTitle`     | Live      | More trustworthy than `detectedAgent`              |

## 2. Read pane output

```bash
mori pane read --pane %56 --lines 80
```

Falls back to tmux if mori output looks stale:
```bash
tmux capture-pane -t %56 -p | tail -30
```

## 3. Send to a pane

**Always use `tmux send-keys`** — it reaches any pane regardless of active status.

**`Enter` must be a bare, unquoted argument.** Inside quotes it is just the word "Enter", not a keypress. Always send text and Enter as separate arguments — or as two separate commands if in doubt:

```bash
# Correct: Enter is a separate unquoted argument
tmux send-keys -t %56 'your message here' Enter

# Also correct: two separate commands (safest)
tmux send-keys -t %56 'your message here'
tmux send-keys -t %56 Enter

# WRONG — Enter is inside the quotes, will not submit:
# tmux send-keys -t %56 'your message here Enter'

# If text is sitting in the input but not submitted
tmux send-keys -t %56 Enter

# Interrupt a busy agent
tmux send-keys -t %56 C-c

# Verify delivery
sleep 1 && tmux capture-pane -t %56 -p | tail -15
```

Why not `mori pane send` or `mori pane message`?
- `mori pane send --pane` is accepted but observed to drop messages silently when the target is not the active pane.
- `mori pane message` routes to the window's active agent only — no `--pane` flag, and if focus shifted, it hits the wrong pane.
- `tmux send-keys -t %<id>` is reliable in all cases.

## Launch a helper agent

Always launch in the **same session and worktree** as the caller. Use `$MORI_WINDOW` to ensure this.

```bash
# 1. Split a new pane (inherits caller's session/worktree via $MORI_WINDOW)
mori pane new --window "$MORI_WINDOW" --split v --name helper --json

# 2. Get its pane ID (window name may have already changed)
HELPER=$(mori pane list --json | jq -r '.[] | select(.paneTitle=="helper") | .tmuxPaneId')

# 3. Launch the agent (CLAUDE_CODE_NO_FLICKER=0 is required — without it, Enter keys won't work)
tmux send-keys -t "$HELPER" 'CLAUDE_CODE_NO_FLICKER=0 claude --model sonnet' Enter

# 4. Wait for it to be ready
until [ "$(mori pane list --json | jq -r --arg id "$HELPER" '.[] | select(.tmuxPaneId==$id) | .agentState')" = "waitingForInput" ]; do sleep 3; done

# 5. Send request
tmux send-keys -t "$HELPER" 'Review plan.md and list top 3 risks.' Enter
```

Model selection: `haiku` for trivial tasks, `sonnet` (default) for normal work, `opus` for hard reasoning.
Add `--permission-mode acceptEdits` if the agent needs to edit files.

## Agent-to-agent messaging

When sending from one agent to another, prefix with sender pane ID so the receiver can reply:

```bash
tmux send-keys -t %60 '[from %31] review plan.md and reply back to %31 when done' Enter
```

The receiver replies:
```bash
tmux send-keys -t %31 '[from %60] done — found 3 risks, see plan.md comments' Enter
```

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Window not found` error | Window name changed (Ghostty renames tabs) | Use `$MORI_WINDOW` or `tmuxPaneId` instead |
| Message dropped silently | Used `mori pane send` to non-active pane | Use `tmux send-keys -t %<id>` instead |
| Message ran as shell command | Sent before agent finished starting | Wait for `agentState == waitingForInput` first |
| Text in input but not processing | `Enter` was inside quotes, not a separate arg | Send `tmux send-keys -t %<id> Enter` |
| Message went to wrong agent | Used `mori pane message` and focus shifted | Use `tmux send-keys -t %<id>` for precise targeting |
| Agent says Write/Edit denied | Launched without edit permissions | Restart with `--permission-mode acceptEdits` |
| `Enter` keys ignored by Claude Code | Missing `CLAUDE_CODE_NO_FLICKER=0` env | Always launch with `CLAUDE_CODE_NO_FLICKER=0 claude ...` |
| `Enter` typed as text, not keypress | `Enter` was inside quotes in `tmux send-keys` | `Enter` must be a bare unquoted arg: `send-keys -t %id 'msg' Enter` |

## Report when done

- Which pane you targeted (tmuxPaneId)
- What the agent replied, or where you read it
- Any recovery step used
