# Addressing: Pane Discovery and ID Resolution

## Why window names fail

Ghostty renames tabs from pane titles. The moment any pane in a tab updates its title (Claude banner loads, pi starts up, a process changes the terminal title), the `windowName` for the whole tab flips. `--window shell` from two minutes ago may now resolve to `--window 2.1.112` or fail entirely.

**Never depend on window names for durable addressing. Always resolve to `tmuxPaneId`.**

## Discovering panes

**Always scope to the current project + worktree first.** Listing all panes dumps every session and makes it impossible to tell which panes belong to your tab.

Inside a mori-managed pane, `MORI_PROJECT` and `MORI_WORKTREE` are set automatically — use them:

```bash
# Peers in the current tab (use this by default)
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
| `agentState` | Live | `running` / `waitingForInput` / `none` |
| `detectedAgent` | Unreliable | Can misidentify (pi reported as claude). Cross-check with `paneTitle` |
| `paneTitle` | Live | Reflects terminal title; more trustworthy than `detectedAgent` |

## Self-discovery inside a Mori pane

When a helper agent launches, it should find and announce its own pane ID immediately:

```bash
# Cleanest: mori native command
mori pane id

# Fallback: env var (set at pane creation)
echo $MORI_PANE_ID

# Fallback: discover from list by title
mori pane list --json | jq -r '.[] | select(.paneTitle=="pi-test") | .tmuxPaneId'
```

Prefer `mori pane id` — it's the most direct. The orchestrator captures this ID so all future sends target by `tmuxPaneId`, not window name.

## Handshake pattern

After spawning a helper, have it announce itself back:

```bash
# Orchestrator sends to helper (after launch):
tmux send-keys -t %60 'echo "READY:$MORI_PANE_ID"' Enter

# Orchestrator reads the announcement:
tmux capture-pane -t %60 -p | grep "READY:"
# → READY:%60
```

Now the orchestrator has the canonical pane ID confirmed by the helper itself.
