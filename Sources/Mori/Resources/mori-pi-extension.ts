// Mori integration for Pi coding agent
// Sets tmux pane options for agent state detection and renames window.

export default function (pi: any) {
  const AGENT_NAME = "pi";

  async function tmux(...args: string[]) {
    try {
      await pi.exec("tmux", args);
    } catch {
      // Not in tmux — ignore silently
    }
  }

  async function setState(state: string) {
    await tmux("set-option", "-p", "@mori-agent-state", state);
    await tmux("set-option", "-p", "@mori-agent-name", AGENT_NAME);
    // rename-window implicitly disables automatic-rename;
    // Mori's stale cleanup re-enables it so tmux picks up the current process name.
    await tmux("rename-window", AGENT_NAME);
  }

  pi.on("agent_start", async () => {
    await setState("working");
  });

  pi.on("agent_end", async () => {
    await setState("done");
  });

  pi.on("tool_execution_start", async () => {
    await setState("working");
  });
}
