# Addressing: Pane Discovery and ID Resolution

## Why window names fail

Ghostty renames tabs from pane titles. The moment any pane in a tab updates its title (Claude banner loads, pi starts up, a process changes the terminal title), the `windowName` for the whole tab flips. `--window shell` from two minutes ago may now resolve to `--window 2.1.112` or fail entirely.

**Never depend on window names for durable addressing. Prefer Mori's tmux ID env vars (`MORI_WINDOW`, `MORI_PANE`) or resolve to `tmuxPaneId`.**

## Discovering panes

**Always scope to the current project + worktree first.** Listing all panes dumps every session and makes it impossible to tell which panes belong to your tab.

Inside a Mori-managed pane, these are set automatically:

| Variable | Meaning | Example | Use |
|---|---|---|---|
| `MORI_PROJECT` | Project name | `mori` | Scope CLI queries |
| `MORI_WORKTREE` | Worktree name | `main` | Scope CLI queries |
| `MORI_SESSION` | tmux session ID | `$1` | tmux-native session addressing |
| `MORI_SESSION_NAME` | tmux session name | `mori/main` | Human-readable session label |
| `MORI_WINDOW` | tmux window ID | `@3` | Stable `--window` value for Mori CLI |
| `MORI_PANE` | tmux pane ID | `%42` | Stable `--pane` value and `tmux -t` target |

Use the env vars first; list panes only when discovering peers:

```bash
# Peers in the current worktree (use this by default)
mori pane list --json | jq --arg p "$MORI_PROJECT" --arg w "$MORI_WORKTREE" \
  '.[] | select(.projectName==$p and .worktreeName==$w)'

# Look up current window name from a stable pane ID
mori pane list --json | jq '.[] | select(.tmuxPaneId=="%56")'

# All panes across all sessions (avoid unless you specifically need cross-session visibility)
mori pane list --json
```

## Key fields

| Field | Reliability | Notes |
|---|---|---|
| `tmuxPaneId` | Stable for the session | Use this as the primary handle for all operations |
| `projectName` | Stable | Set at pane creation |
| `worktreeName` | Stable | Set at pane creation |
| `windowName` | Ephemeral | Changes whenever any pane in the tab updates its title |
| `MORI_WINDOW` | Stable | tmux window ID (`@...`); use this instead of `windowName` when available |
| `MORI_PANE` | Stable | tmux pane ID (`%...`); same value as `tmuxPaneId` for the current pane |
| `agentState` | Live | `running` / `waitingForInput` / `none` |
| `detectedAgent` | Unreliable | Can misidentify (pi reported as claude). Cross-check with `paneTitle` |
| `paneTitle` | Live | Reflects terminal title; more trustworthy than `detectedAgent` |

## Self-discovery inside a Mori pane

When a helper agent launches, it should find and announce its own pane ID immediately:

```bash
# Cleanest: env vars (set at pane creation)
printf 'session=%s window=%s pane=%s\n' "$MORI_SESSION" "$MORI_WINDOW" "$MORI_PANE"

# Mori native command
mori pane id

# Fallback: discover from list by title
mori pane list --json | jq -r '.[] | select(.paneTitle=="pi-test") | .tmuxPaneId'
```

Prefer `$MORI_PANE` for self-addressing. The orchestrator captures this ID so all future sends target by `tmuxPaneId`, not window name.

## Handshake pattern

After spawning a helper, have it announce itself back:

```bash
# Orchestrator sends to helper (after launch):
tmux send-keys -t %60 'echo "READY:$MORI_PANE"' Enter

# Orchestrator reads the announcement:
tmux capture-pane -t %60 -p | grep "READY:"
# → READY:%60
```

Now the orchestrator has the canonical pane ID confirmed by the helper itself.
