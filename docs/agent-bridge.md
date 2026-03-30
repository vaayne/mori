# Agent Bridge

Cross-pane agent discovery, monitoring, and messaging for Mori.

## What Is It?

Mori runs each coding agent (Claude Code, Codex, Pi, etc.) in its own tmux window. By default these agents are isolated — they can't see each other or talk to each other.

The **Agent Bridge** breaks that isolation. It gives every pane a stable identity and provides CLI commands to:

- **Discover** — list all panes and their agent states
- **Observe** — read terminal output from any pane
- **Communicate** — send structured messages between panes
- **Identify** — let an agent know who and where it is

Messages use a simple text envelope that arrives as typed input in the target pane. No shared memory, no sockets between agents, no custom protocols — just tmux and a grep-friendly text format.

## Quick Start

### 1. Check what's running

```bash
$ mori pane list
[
  {
    "projectName": "myapp",
    "worktreeName": "main",
    "windowName": "claude",
    "agentState": "running",
    "detectedAgent": "claude",
    "tmuxPaneId": "%5",
    "endpoint": "local"
  },
  {
    "projectName": "myapp",
    "worktreeName": "main",
    "windowName": "codex",
    "agentState": "waiting",
    "detectedAgent": "codex",
    "tmuxPaneId": "%8",
    "endpoint": "local"
  }
]
```

### 2. Read another agent's output

```bash
$ mori pane read myapp main codex --lines 20
```

Returns the last 20 lines of visible terminal output from the Codex pane.

### 3. Send a message

```bash
$ mori pane message myapp main codex "The API schema changed — update your tests"
```

Codex's pane receives this as typed input:

```
[mori-bridge project:myapp worktree:main window:claude pane:%5] The API schema changed — update your tests
```

### 4. Check your own identity

```bash
$ mori pane id
myapp/main/claude pane:%5
```

## CLI Reference

### `mori pane list`

List all panes across all projects, worktrees, and windows. Output is JSON.

| Field | Description |
|---|---|
| `projectName` | Git repository / project name |
| `worktreeName` | Worktree (branch) name |
| `windowName` | Tmux window title (often the agent name) |
| `agentState` | `running`, `waiting`, `completed`, or `null` |
| `detectedAgent` | Agent name (`claude`, `codex`, `pi`) or `null` |
| `tmuxPaneId` | Tmux pane ID (e.g., `%5`) |
| `endpoint` | `local` or SSH remote identifier |

### `mori pane read <project> <worktree> <window> [--lines N]`

Capture visible terminal output from a pane.

- **Default**: 50 lines
- **Maximum**: 200 lines
- Output is raw text (not JSON)

```bash
# Last 10 lines from the claude window
mori pane read myapp main claude --lines 10
```

### `mori pane message <project> <worktree> <window> <text>`

Send a message to a pane. The message is wrapped in an envelope that includes sender identity, then delivered as typed keystrokes (via `tmux send-keys`) followed by Enter.

```bash
mori pane message myapp main codex "Please review src/auth.ts"
```

The sender's identity is read automatically from `MORI_*` environment variables (set by Mori in each pane's hook context). If unavailable, defaults to `cli/cli/cli`.

### `mori pane id`

Print the current pane's identity. Reads from environment variables:

| Variable | Description | Example |
|---|---|---|
| `MORI_PROJECT` | Project name | `myapp` |
| `MORI_WORKTREE` | Worktree name | `main` |
| `MORI_WINDOW` | Window title | `claude` |
| `MORI_PANE_ID` | Tmux pane ID | `%5` |

Output format: `<project>/<worktree>/<window> pane:<id>`

## Message Envelope Format

Every message is wrapped in a structured, grep-friendly envelope:

```
[mori-bridge project:<project> worktree:<worktree> window:<window> pane:<paneId>] <text>
```

**Example:**

```
[mori-bridge project:myapp worktree:main window:claude pane:%5] Please review the auth module
```

The fields use labeled keys (`project:`, `worktree:`, `window:`, `pane:`) rather than slash-delimited values, so worktree names containing `/` (like `feature/auth`) are handled correctly.

### Parsing Messages

**Bash:**

```bash
if [[ "$line" =~ ^\[mori-bridge\ project:(.+)\ worktree:(.+)\ window:(.+)\ pane:(.+)\]\ (.+)$ ]]; then
  project="${BASH_REMATCH[1]}"
  worktree="${BASH_REMATCH[2]}"
  window="${BASH_REMATCH[3]}"
  pane_id="${BASH_REMATCH[4]}"
  message="${BASH_REMATCH[5]}"
fi
```

**Python:**

```python
import re
m = re.match(r'^\[mori-bridge project:(.+) worktree:(.+) window:(.+) pane:(.+)\] (.+)$', line)
if m:
    project, worktree, window, pane_id, message = m.groups()
```

**Swift (using `AgentMessage.parse`):**

```swift
if let msg = AgentMessage.parse(line) {
    print(msg.fromProject, msg.fromWindow, msg.text)
}
```

## How It Works Internally

### Data Flow

```
Agent A's pane
  │
  ▼
mori pane message myapp main codex "review auth"
  │  reads MORI_* env vars for sender identity
  ▼
CLI sends IPC request over Unix domain socket
  │  IPCCommand.paneMessage(project, worktree, window, text, sender*)
  ▼
Mori app (IPCHandler)
  │  resolveWindow() — case-insensitive match: project → worktree → window
  │  constructs AgentMessage envelope from sender metadata
  ▼
tmux send-keys "<envelope text>" Enter
  │
  ▼
Agent B's pane receives the text as terminal input
```

### Target Resolution

When you specify `<project> <worktree> <window>`:

1. **Project** — matched by name (case-insensitive)
2. **Worktree** — matched within the project (case-insensitive)
3. **Window** — matched by title within the worktree (case-insensitive)
4. **Pane** — the window's active pane (`activePaneId`) receives the command
5. Remote/SSH worktrees use their own `TmuxBackend` instance

If any step fails, you get an error like: `Window not found: myapp/main/codex`

### Sender Identity

The CLI reads sender identity from environment variables set by Mori's hook system:

- `MORI_PROJECT` — which project this pane belongs to
- `MORI_WORKTREE` — which worktree/branch
- `MORI_WINDOW` — the window title
- `MORI_PANE_ID` — the tmux pane ID

These are set when Mori runs hook scripts (see [Agent Hooks](agent-hooks.md)). If you run `mori pane message` from a plain terminal outside Mori, the sender fields default to `cli`.

## UI Features

### Hover Peek

Hover any window row with an agent badge in the sidebar to see the last 8 lines of pane output. The popover appears after 300ms and caches for 5 seconds.

### Quick Reply

Click a "waiting" (❗) badge on any window row to reveal an inline text field. Type a reply and press Enter — the text is sent directly to the pane.

### Agents Sidebar Mode

The sidebar has an **Agents** mode (alongside Tasks and Workspaces) showing all agent windows grouped by state:

| Group | Meaning |
|---|---|
| **Attention** | Waiting for input or errored |
| **Running** | Actively executing |
| **Completed** | Finished successfully |
| **Idle** | Agent detected but inactive |

### Agent Dashboard

Press **⌘⇧A** to toggle a floating dashboard showing live output from all agent panes. Auto-refreshes every 5 seconds, pauses when hidden.

## Use Cases

### Delegate a Subtask

You're in Claude working on a feature. Ask Codex to handle the tests:

```bash
mori pane message myapp main codex "Write unit tests for UserService in src/services/user.ts. Run them and fix any failures."
```

Check back later:

```bash
mori pane read myapp main codex --lines 30
```

### Coordinate File Ownership

Prevent two agents from editing the same files:

```bash
mori pane message myapp main codex "I'm refactoring src/auth/ — don't touch those files until I message you again."
```

### Cross-Branch Communication

Agent on `feat/api` tells agent on `feat/ui` about an API change:

```bash
mori pane message myapp feat/ui pi "UserDTO.role is now UserDTO.roles (string → string[]). Update your fetch calls."
```

### Build/Test Watcher

A script in one pane notifies the coding agent when tests break:

```bash
while true; do
  output=$(mise run test 2>&1)
  if echo "$output" | grep -q "FAILED"; then
    mori pane message myapp main claude "Tests failed. Output: $(echo "$output" | tail -5)"
  fi
  sleep 60
done
```

### Escalation

A less capable agent escalates a hard problem:

```bash
mori pane message myapp main claude "Stuck on Swift 6 sendability error in TmuxBackend.swift:142. Can you take a look?"
```

### Orchestrator Pattern

One agent coordinates multiple workers:

```bash
# Orchestrator distributes work
mori pane message myapp main claude "Implement the caching layer in src/cache/"
mori pane message myapp main codex "Update API docs in docs/api.md"
mori pane message myapp feat/ui pi "Build the settings form per the Figma spec"

# Poll for completion
for agent in claude codex pi; do
  echo "=== $agent ==="
  mori pane read myapp main $agent --lines 5
done
```

### Agent Self-Discovery

An agent can learn about its environment and peers:

```bash
# Who am I?
mori pane id

# Who else is running?
mori pane list | jq '.[] | select(.agentState == "running") | .windowName'
```

## Teaching Agents to Use the Bridge

Add this to the agent's skill file, system prompt, or `AGENTS.md`:

```markdown
## Inter-Agent Communication

You can communicate with other coding agents via the `mori` CLI:

- **List agents**: `mori pane list` — JSON list of all panes with agent state
- **Read output**: `mori pane read <project> <worktree> <window> --lines 50`
- **Send message**: `mori pane message <project> <worktree> <window> "your message"`
- **Your identity**: `mori pane id`

Messages arrive as text input in the format:
`[mori-bridge project:<p> worktree:<w> window:<win> pane:<id>] <text>`

When you see a message in this format, it's from another agent. Read the sender
coordinates and the message text, then respond appropriately.
```

## Best Practices

1. **Keep messages short and actionable.** The message is typed as keystrokes into a terminal — extremely long messages may be slow or get truncated by the agent's input handling.

2. **Use `pane list` before messaging.** Verify the target pane exists and check its `agentState` — sending to a pane with no running agent just types text into a shell.

3. **Use `pane read` to check results.** Don't assume a message was acted on. Read the target's output to confirm.

4. **Include context in messages.** The recipient has no shared memory with you. Mention file paths, branch names, and what you expect them to do.

5. **Avoid message loops.** If two agents are instructed to message each other on completion, they can ping-pong forever. Design one-directional flows or use a coordinator.

6. **Don't send secrets in messages.** Envelope text is visible in tmux scrollback and may be logged by the receiving agent.

7. **Prefer `pane read` over asking.** Reading an agent's output is instant and non-disruptive. Sending a message interrupts whatever the agent is doing.

8. **Use the Agents sidebar for human oversight.** The sidebar shows all agent states at a glance. Use ⌘⇧A dashboard for live multi-agent monitoring.

## Limitations

- **One-way delivery.** Messages are fire-and-forget. There's no delivery confirmation or read receipt — use `pane read` to check if the agent responded.
- **No message queue.** If the target agent isn't waiting for input, the message appears as unexpected terminal input. The agent may ignore it, misinterpret it, or error.
- **Text-only.** Messages are plain text delivered as keystrokes. No binary data, no structured payloads beyond the envelope format.
- **Single active pane.** In multi-pane windows, only the active pane receives messages.
- **Environment variables required.** `mori pane id` and sender metadata in `mori pane message` depend on `MORI_*` environment variables. These are set by Mori's hook system — if hooks aren't enabled, sender identity defaults to `cli`.

## Architecture

| Layer | Component | Location |
|---|---|---|
| **Model** | `AgentMessage` — envelope struct with `format`/`parse` | `Packages/MoriCore/Sources/MoriCore/Models/AgentMessage.swift` |
| **IPC** | `IPCCommand.paneMessage` / `.paneList` / `.paneRead` | `Packages/MoriIPC/Sources/MoriIPC/IPCProtocol.swift` |
| **CLI** | `mori pane {list,read,message,id}` subcommands | `Sources/MoriCLI/MoriCLI.swift` |
| **Handler** | `IPCHandler` — resolves targets, sends via tmux | `Sources/Mori/App/IPCHandler.swift` |
| **Tests** | Envelope format, parse, Codable round-trip | `Packages/MoriCore/Tests/MoriCoreTests/main.swift` |

## See Also

- [Agent Hooks](agent-hooks.md) — how Mori detects agent state and sets `MORI_*` environment variables
- [Architecture](architecture.md) — package structure and data flow
- [Keymaps](keymaps.md) — keyboard shortcuts including ⌘⇧A for the agent dashboard
