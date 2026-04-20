---
name: mori-agent-bridge
description: >
  Use Mori CLI to enable agent-to-agent communication and coordination across
  Mori-managed panes. Use this whenever you need to launch a helper agent, send
  a message to another agent (Claude, Pi, Codex), read another agent's output,
  coordinate multi-agent workflows, or enable bidirectional agent communication.
  Prefer this over ad-hoc tmux whenever the task involves mori pane operations
  or agent-to-agent messaging.
---

# Mori Agent Bridge

Primary use case: **agents communicating with each other** via mori + tmux.

Three operations:
1. **Observe** — `mori pane read` (non-disruptive, always try this first)
2. **Send** — `tmux send-keys -t %<id>` (the only reliable primitive; see [send-receive.md](references/send-receive.md))
3. **Discover** — `mori pane list --json` (resolve pane IDs before anything else)

## Golden rule

> Always resolve `tmuxPaneId` first. Never address by window name alone — window names churn.

```bash
# Discover peers in the current tab (MORI_PROJECT/MORI_WORKTREE are set by mori automatically)
mori pane list --json | jq --arg p "$MORI_PROJECT" --arg w "$MORI_WORKTREE" \
  '.[] | select(.projectName==$p and .worktreeName==$w)'

# Read any pane (reliable)
mori pane read --pane %56 --lines 80

# Send to any pane (reliable)
tmux send-keys -t %56 'your message' Enter

# Verify delivery
tmux capture-pane -t %56 -p | tail -20
```

## Message envelope (agent-to-agent)

When one agent sends to another, prefix the message so the receiver knows who sent it and where to reply. Always include a reply instruction so the receiver pushes back to you — no polling needed.

```
[FROM:claude:%31 TO:pi:%60] please review plan.md and reply with risks.
When done, send: tmux send-keys -t %31 '[FROM:pi:%60 TO:claude:%31] <your summary>' Enter
```

The receiver strips the prefix, processes the request, then sends back directly. The orchestrator just waits for input rather than polling.

## Reference files

Read the relevant file for your task — don't load all of them:

| Task | Read |
|---|---|
| Finding panes, resolving IDs, window name churn | [references/addressing.md](references/addressing.md) |
| Sending messages, key routing, envelope protocol | [references/send-receive.md](references/send-receive.md) |
| Step-by-step workflows (launch / message / observe) | [references/workflows.md](references/workflows.md) |
| Something broke | [references/failure-modes.md](references/failure-modes.md) |
| Multi-agent orchestration, bidirectional comms | [references/orchestrator.md](references/orchestrator.md) |

## Report when done

- Which pane you targeted (tmuxPaneId)
- What the agent replied, or where you read it
- Any recovery step used (C-c, tmux fallback, rediscover)
