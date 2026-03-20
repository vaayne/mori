// Mori integration for Pi coding agent
// Install: ~/.pi/agent/extensions/mori-tmux.ts
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

  async function saveOriginalName() {
    try {
      const result = await pi.exec("tmux", [
        "show-option",
        "-pqv",
        "@mori-original-name",
      ]);
      if (!result?.stdout?.trim()) {
        const name = await pi.exec("tmux", [
          "display-message",
          "-p",
          "#{window_name}",
        ]);
        await tmux(
          "set-option",
          "-p",
          "@mori-original-name",
          name?.stdout?.trim() || ""
        );
      }
    } catch {
      // ignore
    }
  }

  async function getDirName(): Promise<string> {
    try {
      const result = await pi.exec("tmux", [
        "display-message",
        "-p",
        "#{pane_current_path}",
      ]);
      const path = result?.stdout?.trim() || "";
      return path.split("/").pop() || "";
    } catch {
      return "";
    }
  }

  async function setState(state: string, emoji: string) {
    const dirName = await getDirName();
    await tmux("set-option", "-p", "@mori-agent-state", state);
    await tmux("set-option", "-p", "@mori-agent-name", AGENT_NAME);
    await saveOriginalName();
    await tmux("rename-window", `${emoji} ${AGENT_NAME} ${dirName}`);
  }

  pi.on("agent_start", async () => {
    await setState("working", "⚡");
  });

  pi.on("agent_end", async () => {
    await setState("done", "✅");
  });

  pi.on("tool_execution_start", async () => {
    await setState("working", "⚡");
  });
}
