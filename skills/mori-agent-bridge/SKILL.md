---
name: mori-agent-bridge
description: >
  Multi-agent collaboration via the Mori Agent Bridge. Use when multiple coding
  agents (Claude Code, Codex, Pi, etc.) need to work together — e.g., one agent
  writes code and asks another to review it, the reviewer sends feedback back,
  and the original agent continues. Handles agent discovery, output observation,
  and structured messaging between Mori-managed panes.
---

# Mori Agent Bridge

Mori runs each coding agent in its own tmux window. The Agent Bridge lets agents
discover, observe, and message each other — enabling real collaboration workflows
like: write → review → feedback → continue.

## Your Identity

Every Mori-managed pane has these environment variables set automatically:

| Variable | Description | Example |
|---|---|---|
| `MORI_PROJECT` | Project name | `myapp` |
| `MORI_WORKTREE` | Worktree / branch | `main` |
| `MORI_WINDOW` | Window (tab) name | `claude` |
| `MORI_PANE_ID` | tmux pane ID | `%5` |

```bash
# Print your full identity
mori pane id
# → myapp/main/claude pane:%5
```

When these env vars are set (i.e., you are inside a Mori terminal), all `--project`,
`--worktree`, and `--window` flags default to your own context. You only need to
supply flags when addressing a *different* target.

## Discover Other Agents

```bash
# List all panes — JSON with agent state
mori pane list --json

# Find which agents are waiting for input
mori pane list --json | jq '.[] | select(.agentState == "waiting") | .windowName'

# Find running agents
mori pane list --json | jq '.[] | select(.agentState == "running") | .windowName'
```

Each entry includes:
- `windowName` — the agent's window name (use this to address it)
- `agentState` — `running`, `waiting`, `completed`, or `null`
- `detectedAgent` — `claude`, `codex`, `pi`, or `null`
- `tmuxPaneId` — tmux pane ID (`%N`)
- `projectName`, `worktreeName` — scope

## Read Another Agent's Output

```bash
# Last 50 lines from the "codex" window (default)
mori pane read --window codex

# More lines
mori pane read --window codex --lines 100

# By pane ID
mori pane read --pane %8 --lines 30

# Cross-worktree
mori pane read --project myapp --worktree feat/ui --window pi --lines 50
```

Max 200 lines. Use this to check whether the other agent has responded before
sending another message.

## Send a Message

```bash
# Message another window in the same project/worktree
mori pane message "Please review src/auth.ts for correctness" --window codex

# Cross-worktree
mori pane message "UserDTO.role is now roles (string[]). Update fetch calls." \
  --project myapp --worktree feat/ui --window pi
```

Your sender identity is filled automatically from `MORI_*` env vars.

The receiving pane sees the message as typed terminal input:

```
[mori-bridge project:myapp worktree:main window:claude pane:%5] Please review src/auth.ts for correctness
```

## Receiving Messages

When a line matches this pattern, it is from another Mori agent:

```
[mori-bridge project:<p> worktree:<w> window:<win> pane:<id>] <text>
```

Read the sender's `window` field to know who sent it, then act on `<text>`.

To reply, send a message back to that window:

```bash
mori pane message "Review done — two issues in lines 42 and 87, see above" --window claude
```

## Collaboration Workflows

### Write → Review → Feedback → Continue

**Agent A (Claude Code) — write code and request review:**

```bash
# Finish implementing the feature, then:
mori pane message "I've implemented UserService in src/services/user.ts. Please review for correctness and edge cases, then message me back." --window codex
# Continue on other work or wait
```

**Agent B (Codex) — review and send feedback:**

```bash
# Read what Claude wrote
mori pane read --window claude --lines 50

# ... review the code ...

# Send feedback back
mori pane message "Found two issues: (1) line 42 does not handle null userId — add a guard. (2) line 87 has a race condition if called concurrently. Otherwise LGTM." --window claude
```

**Agent A — receive feedback and continue:**

```bash
# The message arrives as terminal input; Claude reads it and applies fixes
# After fixing:
mori pane message "Fixed both issues. Ready for final approval." --window codex
```

---

### Orchestrator Distributes Work

**Orchestrator agent:**

```bash
mori pane message "Implement the caching layer in src/cache/. Message me when done." --window claude
mori pane message "Update API docs in docs/api.md to match the new endpoints. Message me when done." --window codex

# Poll for completion
for agent in claude codex; do
  echo "=== $agent ==="
  mori pane read --window $agent --lines 5
done
```

---

### Subtask Delegation

```bash
# Delegate tests to Codex
mori pane message "Write unit tests for UserService in src/services/user.ts. Run them, fix failures, then message me with the result." --window codex

# Do your own work, then check back
mori pane read --window codex --lines 30
```

---

### Escalation

```bash
# Stuck on something — ask a more capable agent
mori pane message "Stuck on Swift 6 sendability error in TmuxBackend.swift:142. Can you take a look and message me the fix?" --window claude
```

---

### Build/Test Watcher

```bash
while true; do
  output=$(mise run test 2>&1)
  if echo "$output" | grep -q "FAILED"; then
    mori pane message "Tests failed: $(echo "$output" | tail -5)" --window claude
  fi
  sleep 60
done
```

---

### Check Agent State Before Messaging

Only message an agent that is `waiting` (ready for input):

```bash
state=$(mori pane list --json | jq -r '.[] | select(.windowName=="codex") | .agentState')
if [[ "$state" == "waiting" ]]; then
  mori pane message "subtask ready for review" --window codex
else
  echo "Codex is $state — check back later"
fi
```

## Rules

1. **Keep messages short and actionable.** Messages are delivered as keystrokes — very long messages may be slow or truncated.
2. **Check `agentState` before messaging.** Sending to a pane that is `running` interrupts it mid-task; wait for `waiting`.
3. **Use `pane read` to confirm action.** Messages are fire-and-forget; no receipt. Read the target's output to verify it responded.
4. **Include full context.** The recipient has no shared memory with you — include file paths, branch names, what you expect.
5. **Avoid message loops.** Two agents instructed to message each other on completion will ping-pong. Design one-directional flows or use a coordinator.
6. **No secrets.** Envelope text is visible in tmux scrollback and may be logged by the receiving agent.
7. **Prefer `pane read` over interrupting.** Reading output is instant and non-disruptive; messaging stops whatever the agent is doing.
