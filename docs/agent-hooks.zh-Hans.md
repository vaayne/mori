# Agent Hooks（代理钩子）

Mori 可与编程代理（Claude Code、Codex CLI、Pi）集成，在标签页名称中显示其状态并发送通知。钩子通过**设置 > Agent Hooks** 手动启用/禁用——不会自动安装。

## 工作原理

启用后，每个代理会安装钩子脚本，通过 tmux 窗格选项报告状态变化：
- `@mori-agent-state`：`"working"`（代理运行中）或 `"done"`（代理已完成）
- `@mori-agent-name`：代理名称（例如 `"claude"`、`"codex"`、`"pi"`）

在 Mori 的 5 秒轮询周期中，它直接从 tmux 读取这些选项——无需进程扫描，无需模式匹配。标签页名称会显示代理名称（如 `claude`、`codex`、`pi`），侧边栏显示徽章（⚡ 运行中 / ✅ 已完成）。完成时会发送 macOS 通知。

## 安装

### Claude Code

1. 打开 Mori 设置 > Agent Hooks
2. 开启 **Claude Code**
3. Mori 会更新 `~/.claude/settings.json`，添加以下事件的钩子：
   - `UserPromptSubmit`（提交提示词）
   - `Stop`（代理停止）
   - `Notification`（完成通知）

在 tmux 窗口中运行 Claude Code。运行期间标签页会重命名为 `claude`（侧边栏显示 ⚡ 徽章），完成后恢复默认名称（显示 ✅ 徽章）。

### Codex CLI

1. 打开 Mori 设置 > Agent Hooks
2. 开启 **Codex CLI**
3. Mori 会创建/更新 `~/.codex/config.toml`：
   ```toml
   # Mori agent status hook
   notify = ["/Users/you/.config/mori/hooks/mori-codex-hook.sh"]
   ```

**注意：** `notify` 条目必须位于 TOML 文件的**顶层**（在任何 `[section]` 标题之前）。Mori 会自动确保这一点。

在 tmux 窗口中运行 Codex。运行期间标签页会重命名为 `codex`（侧边栏显示 ⚡ 徽章），完成后恢复默认名称（显示 ✅ 徽章）。

### Pi

1. 打开 Mori 设置 > Agent Hooks
2. 开启 **Pi**
3. Mori 会在 `~/.config/mori/mori-pi-extension.ts` 创建 TypeScript 扩展，并在 `~/.pi/agent/settings.json` 中注册：
   ```json
   {
     "extensions": [
       "~/mori-pi-extension.ts"
     ]
   }
   ```

在 tmux 窗口中运行 Pi。运行期间标签页会重命名为 `pi`（侧边栏显示 ⚡ 徽章），完成后恢复默认名称（显示 ✅ 徽章）。

## 钩子脚本

钩子脚本存储在 `$XDG_CONFIG_HOME/mori/hooks/`（备选路径：`~/.config/mori/hooks/`），从 Mori 的 bundle 资源中加载。它们是共享的 shell/TypeScript 工具：

### mori-hook-common.sh
被代理专用脚本引用的共享 bash 函数。设置 `@mori-agent-state` 和 `@mori-agent-name` 窗格选项，然后将 tmux 窗口重命名为代理名称。

### mori-agent-hook.sh（Claude Code）
响应 Claude Code 钩子事件：
- `UserPromptSubmit` → 状态：`"working"`
- `Stop`、`Notification` → 状态：`"done"`

读取 stdin（Claude Code 通过管道传入 JSON 钩子数据），不在 tmux 中时静默退出。

### mori-codex-hook.sh（Codex CLI）
处理旧版 Codex `notify` 钩子（JSON 作为参数 1）：
```bash
# 旧版格式 (Codex < 2.0)
notify = ["/path/to/mori-codex-hook.sh"]
# 钩子接收: mori-codex-hook.sh '{"type":"agent-turn-complete",...}'
```

如果 Codex 添加了显式钩子事件，也支持新版基于事件的格式。

### mori-pi-extension.ts（Pi）
监听 Pi 事件的 TypeScript 扩展：
- `agent_start`、`tool_execution_start` → 状态：`"working"`
- `agent_end` → 状态：`"done"`

## 禁用钩子

在设置 > Agent Hooks 中关闭对应代理。Mori 会移除：
- `~/.config/mori/hooks/` 中的钩子脚本
- 代理配置文件中的钩子条目（`~/.claude/settings.json`、`~/.codex/config.toml` 等）

如果手动删除了钩子脚本，先关闭再重新开启即可重新安装。

## 过期清理

当通过钩子检测到的代理退出时（tmux 窗格回到 shell），Mori 会自动：
1. 清除 `@mori-agent-state` 和 `@mori-agent-name` 窗格选项
2. 重新启用 `automatic-rename`，让 tmux 将窗口名称更新为当前进程

这可以防止代理停止后残留过期的代理名称。

## 通知

当代理完成时（状态：`"done"`），Mori 会发送 macOS 通知：
- **标题**：`"Claude Code Finished"`（或 `"Codex Finished"` 等）
- **内容**：窗口标题和工作树名称
- **声音**：系统默认提示音

点击通知可聚焦到对应窗口。打包的 `.app` 使用 `UNUserNotificationCenter`；未打包的 `swift run` 构建回退到 `osascript`。

## 故障排除

**钩子似乎没有触发：**
- 确认钩子脚本存在：`ls ~/.config/mori/hooks/`
- 检查代理配置文件是否正确更新：
  - Claude Code：`cat ~/.claude/settings.json | grep mori`
  - Codex：`cat ~/.codex/config.toml | grep mori`
  - Pi：`cat ~/.pi/agent/settings.json | grep mori`
- 确保代理在 _tmux 会话内_ 运行。钩子仅在 tmux 中有效。

**标签页名称未更改为代理名称：**
- 切换到其他窗口再切回来以重新加载 Mori 的 tmux 轮询，或重启 Mori。
- 执行 `tmux list-panes -F "#{pane_id} #{@mori-agent-state} #{@mori-agent-name}"` 查看窗格选项是否已设置。
- 即使标签页名称尚未更新，侧边栏徽章也应显示（确认是否显示 ⚡ 或 ✅）。

**钩子脚本权限被拒绝：**
- 通过设置 > Agent Hooks 重新安装（先关闭再开启）。Mori 安装时会设置 `0755` 权限。

**Codex notify 行未被添加：**
- 确认 `~/.codex/config.toml` 存在且可读。
- 如果在 Codex 创建文件后才添加 Mori 钩子，请关闭/开启钩子以重试。
- 检查文件是否有语法错误（TOML 解析器可能会拒绝）。

## 实现细节

**AgentHookConfigurator**（Swift）：
- 检测已安装的钩子：`isClaudeHookInstalled()`、`isCodexHookInstalled()`、`isPiExtensionInstalled()`
- 安装/卸载：`installClaudeHook()`、`uninstallClaudeHook()` 等
- 处理代理配置文件变更（Claude/Pi 用 JSON，Codex 用 TOML）

**WorkspaceManager**（Swift）：
- 在 5 秒 tmux 轮询中读取 `@mori-agent-state` 和 `@mori-agent-name`
- 将钩子状态映射为内部状态（`"working"` → `.running`，`"done"` → `.completed`）
- 更新 `RuntimeWindow.detectedAgent` 和窗口徽章
- 代理退出时清除过期窗格选项

**TmuxBackend**（Swift）：
- 新方法：`unsetPaneOption()`、`setWindowOption()`
- TmuxParser 在窗格格式字符串中包含代理字段

**TmuxCommandRunner**（Swift）：
- 改进的环境加载：优先检查继承的 PATH（即时），回退到登录 shell 并设置 10 秒超时
- 防止在 `.app` bundle 启动时因最小环境而挂起

## 相关文件

- `Sources/Mori/App/AgentHookConfigurator.swift` — 钩子安装/卸载逻辑
- `Sources/Mori/App/WorkspaceManager.swift` — 钩子状态读取和清理
- `Sources/Mori/App/NotificationManager.swift` — 通知中的代理名称
- `Sources/Mori/Resources/mori-*.sh` — 钩子脚本
- `Sources/Mori/Resources/mori-pi-extension.ts` — Pi 扩展
- `Packages/MoriCore/Models/RuntimeWindow.swift` — 添加 `detectedAgent` 字段
- `Packages/MoriTmux/Sources/MoriTmux/TmuxBackend.swift` — 窗格选项读写
- `Packages/MoriUI/Sources/MoriUI/GhosttySettingsView.swift` — Agent Hooks 设置标签页

## 另请参阅

- [键盘快捷键](keymaps.zh-Hans.md)
- CLAUDE.md — Agent-Aware Tabs 章节
