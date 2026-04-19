// Mori integration for Pi coding agent
// Sets tmux pane options for agent state detection and renames window.

export default function (pi: any) {
  const AGENT_NAME = "pi";
  const paneTarget = process.env.TMUX_PANE;

  async function tmux(...args: string[]) {
    try {
      await pi.exec("tmux", args);
    } catch {
      // Not in tmux — ignore silently
    }
  }

  async function setState(state: string) {
    if (!paneTarget) return;
    await tmux("set-option", "-p", "-t", paneTarget, "@mori-agent-state", state);
    await tmux("set-option", "-p", "-t", paneTarget, "@mori-agent-name", AGENT_NAME);
    await tmux("select-pane", "-t", paneTarget, "-T", AGENT_NAME);
  }

  pi.on("agent_start", async () => {
    await setState("working");
  });

  pi.on("agent_end", async () => {
    await setState("waiting");
  });

  pi.on("tool_execution_start", async () => {
    await setState("working");
  });
}
