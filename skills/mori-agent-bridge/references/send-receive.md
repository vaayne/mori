# Sending and Receiving: Key Routing and Message Protocol

## Decision table

| Goal | Use |
|---|---|
| Read a pane's output | `mori pane read --pane %<id>` |
| Send to mori's native agent channel (mori-aware attribution) | `mori pane message --window <name>` |
| Send to a specific pane reliably (active or not) | `tmux send-keys -t %<id>` |

`mori pane message` uses mori's built-in routing and is fine when precise pane targeting isn't needed. Use `tmux send-keys` when you need to reach a specific pane ID or when window names can't be trusted.

## Routing table

| Operation | Command | `--pane` works? | Reaches non-active panes? |
|---|---|---|---|
| Read output | `mori pane read --pane %<id>` | ✅ yes | ✅ yes |
| Send to active agent in window | `mori pane message --window <name>` | ❌ no flag | window's active agent only |
| Send raw keys (mori) | `mori pane send --pane %<id>` | accepted but unreliable | ❌ drops silently (observed) |
| Send raw keys (tmux) | `tmux send-keys -t %<id>` | ✅ yes | ✅ yes |

> Observed behavior as of testing — not a confirmed permanent bug. Re-test after mori updates.

## Sending messages

```bash
# Send text and submit
tmux send-keys -t %56 'your message here' Enter

# Interrupt a busy agent
tmux send-keys -t %56 C-c

# Special keys
tmux send-keys -t %56 Escape
tmux send-keys -t %56 Tab
```

## Reading output

```bash
# Via mori (preferred for structured output)
mori pane read --pane %56 --lines 80

# Via tmux (useful sanity check if mori output looks stale)
tmux capture-pane -t %56 -p | tail -20
```

## Message envelope (skill-level convention)

The `[FROM:... TO:...]` envelope is a **skill-level convention** — it is not a built-in Mori format. It works because LLMs understand the convention and act on it; mori itself does not parse it.

Use it to add sender identity so the receiver knows who sent the message and where to reply.

**When to use native `mori pane message` instead:**
- You want mori-native attribution and don't need precise pane targeting
- The target is the window's active agent and window names are stable

**When to use the envelope + tmux:**
- You need to target a specific pane ID regardless of active state
- You're building a multi-agent thread where both sides need to know each other's pane

### Envelope format

```
[FROM:<agent>:<pane-id> TO:<agent>:<pane-id>] <message>
```

### Reply instruction (push model)

Include a reply instruction so the helper pushes back when done — preferred over polling when the helper can execute shell commands.

**Simplest form — use `mori_reply` (see below):**

```
[FROM:claude:%31 TO:pi:%60] review plan.md.
When done, run: mori_reply "pi:%60" "%31" "done: <your summary>"
```

**Without the helper — use two separate tmux calls:**

```
[FROM:claude:%31 TO:pi:%60] review plan.md.
When done, run these two commands:
  tmux send-keys -t %31 '[FROM:pi:%60 TO:claude:%31] <summary>'
  tmux send-keys -t %31 Enter
```

**Why two commands?** `Enter` is only treated as an actual keypress when it is a standalone argument to `tmux send-keys`. If it appears inside a quoted string it is just the word "Enter". Two separate calls make this unambiguous.

> Push relies on the helper obeying the reply instruction. If the helper cannot run shell commands, fall back to polling (see [orchestrator.md](orchestrator.md)).

> Keep messages and reply instructions short. Very long strings injected via `tmux send-keys` can be fragile or truncated.

### `mori_reply` helper

Define this in the helper agent's shell once to avoid quoting footguns in reply instructions:

```bash
mori_reply() {
  local from="$1" to_pane="$2" msg="$3"
  tmux send-keys -t "$to_pane" "[FROM:${from} TO:claude:${to_pane}] ${msg}"
  tmux send-keys -t "$to_pane" Enter
}
# Usage: mori_reply "pi:%61" "%31" "done: reviewed plan.md, 3 risks found"
```

Two separate calls ensure `Enter` is always an actual keypress, never the literal word.

### Parsing the envelope

Strip `[FROM:... TO:...] ` before processing. `TO` confirms it's for you; `FROM` is the reply address.

## Quoting and escaping

Shell metacharacters in messages (`'`, `"`, `` ` ``, `$`, `\`, `|`, `;`) can break `tmux send-keys` or get interpreted by the shell.

**Single quotes inside single-quoted strings** — use `'"'"'`:
```bash
tmux send-keys -t %60 'it'"'"'s done' Enter
```

**Dollar signs and backticks** — use single quotes to prevent shell expansion:
```bash
tmux send-keys -t %60 'echo $MORI_PANE_ID' Enter  # good — literal string
tmux send-keys -t %60 "echo $MORI_PANE_ID" Enter  # bad — expanded by YOUR shell first
```

**Multiline messages** — split into sequential sends:
```bash
tmux send-keys -t %60 'Point 1.' Enter
tmux send-keys -t %60 'Point 2.' Enter
```

**Security:** `tmux send-keys` injects keystrokes directly into the target pane. Never send secrets, tokens, or passwords — they appear in terminal history and scrollback.

## Verifying delivery

```bash
tmux send-keys -t %56 'your message' Enter
sleep 2
tmux capture-pane -t %56 -p | tail -15
```

If text is sitting in the input area unsubmitted, send `Enter`:

```bash
tmux send-keys -t %56 Enter
```
