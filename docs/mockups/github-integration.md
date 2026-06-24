# GitHub 集成 — 提案 mockup

> 配套可视化：[`github-integration.html`](./github-integration.html)（浏览器打开，顶部按钮切换 Tier 1 / Tier 2 / 叠加）

让 Mori 更好地管理 PR，但**不**嵌 github.com 整页 WebView（认证两套 token、不 native、脱离 worktree 上下文）。分两层落地。

## Tier 1 — `gh dash` 作为 companion tool（性价比最高，先做）

把官方扩展 [`gh dash`](https://github.com/dlvhdr/gh-dash) 当成一个内嵌 TUI，跑在右侧 ~420pt 的 companion pane，⌥G 唤起 —— 完全复用现有的 lazygit 集成架构（`CompanionToolPaneController`）。

- 新增 `CompanionTool.githubDash` 枚举值 + 一个键位，几乎零新 UI。
- PR / Issue 列表、review 队列、checkout、评论、看 diff，全在终端里。
- 前提：用户已装 `gh` 和 `gh-dash` 扩展（启动时探测，缺了给一行提示）。

## Tier 2 — worktree PR 状态条（小幅 native，让它有上下文）

每个 worktree 行下挂一条 PR 状态条，绑定该 branch：

- `gh pr view <branch> --json number,state,statusCheckRollup,reviewDecision`
- 显示 编号 / 状态（open·draft·review）/ CI checks（✓ ✕ ●）。
- 点击 → checkout 或 `gh pr view --web`。
- 新建 `MoriGitHub` 包，沿用 `MoriGit` 的 actor + 轮询模式（`GitStatusCoordinator` 同款）。

这是 Mori 比裸 `gh` 强的地方：把 GitHub 状态钉在 worktree 上。

## 暂不做 — Tier 3 富 PR WebView

真要内嵌富 diff / review 线程，再考虑只嵌**单个 PR URL** 的 WKWebView（注入 `gh auth token`）。先验证前两层需求，大概率发现不需要。

---

**本 PR 只含 mockup，无功能代码。** 确认方向后再分 Tier 实现。
