<p align="center">
  <img src="assets/banner.svg" alt="Mori" width="600">
</p>

<p align="center">
  <a href="README.md">English</a> | <b>中文</b>
</p>

Mori 是一款专为多分支并行开发设计的 macOS 终端。不再需要在匿名标签页间反复切换，也不会在上下文切换时丢失 tmux 状态——Mori 为每个分支维护独立的持久化环境，并通过侧边栏一键切换。

## 核心概念

Mori 将开发层级直接映射到 tmux：

```
Project  项目（git 仓库）
└── Worktree  工作树（分支）       ← tmux 会话  例如 myapp/feat-auth
    ├── Window  窗口（标签页）     ← tmux 窗口  例如 "shell"
    │   ├── Pane  面板（左侧分屏） ← tmux 面板
    │   └── Pane  面板（右侧分屏） ← tmux 面板
    └── Window  窗口（标签页）     ← tmux 窗口  例如 "logs"
        └── Pane  面板
```

- **Project（项目）** — 一个 git 仓库。Mori 通过根路径和短名称来跟踪它。
- **Worktree（工作树）** — 某个分支的 `git worktree` 检出目录。每个工作树拥有独立的目录和专属的 tmux 会话（`<项目短名>/<分支名>`）。关闭应用、隔天再打开——会话依然在那里。
- **Window（窗口）** — 工作树会话中的 tmux 窗口，相当于标签页。
- **Pane（面板）** — 窗口中的 tmux 面板，相当于分屏。

侧边栏展示所有项目及其工作树。点击工作树，终端即附加到对应会话。工作树间切换瞬间完成，运行中的程序不会丢失。

## 功能特性

- **项目优先导航** — 通过侧边栏在仓库和分支间切换，而非匿名标签页
- **持久化会话** — 关闭应用后重新打开，tmux 保持一切运行
- **工作树隔离** — 同一仓库的多个分支并行运行，互不干扰
- **本地 + SSH** — 支持本地目录和远程仓库，UI 始终在 Mac 上
- **CLI（`mori`）** — 从终端控制应用，专为 Agent 工作流设计
- **MoriRemote** — 离开 Mac 时通过 iPhone/iPad 伴侣应用进行 SSH/tmux 访问
- **GPU 渲染终端** — libghostty（Ghostty 的引擎）搭配 Metal 加速

## 安装

```bash
brew tap vaayne/tap
brew install --cask mori
```

或从 [GitHub Releases](https://github.com/vaayne/mori/releases) 下载。MoriRemote iOS 版本可在 [TestFlight](https://testflight.apple.com/join/k2GFJPC2) 获取。

## 构建

需要 macOS 14+、tmux、[mise](https://mise.jdx.dev/)、Zig 0.15.2 和 Xcode。

```bash
mise run build    # Debug 构建（自动引导 libghostty）
mise run dev      # 构建并运行
mise run test     # 运行所有测试
```

## CLI

`mori` CLI 通过 Unix socket 与运行中的应用通信，若应用未启动则自动拉起。所有命令支持 `--json` 输出机器可读格式。

地址标志（`--project`、`--worktree`、`--window`、`--pane`）默认读取 Mori 在每个终端面板中设置的 `MORI_*` 环境变量——在 Mori 会话内部可以完全省略这些标志。

```bash
# 项目
mori project list
mori project open .                          # 注册当前目录

# 工作树
mori worktree list --project myapp
mori worktree new feat/auth --project myapp  # 创建 git 工作树 + tmux 会话
mori worktree delete --project myapp --worktree feat/auth

# 窗口（工作树会话中的标签页）
mori window list --project myapp --worktree main
mori window new  --name logs                 # 在 Mori 终端内可感知上下文
mori window rename logs --window shell
mori window close --window logs

# 面板（窗口中的分屏）
mori pane list                               # 列出当前窗口中的面板
mori pane new --split h                      # 水平分屏
mori pane send "npm test Enter"              # 向活动面板发送按键
mori pane read --lines 100                   # 捕获面板输出
mori pane rename agent --pane %3
mori pane close --pane %3

# 导航
mori focus --project myapp --worktree feat/auth
mori focus --window logs                     # 聚焦窗口（感知上下文）

# Agent 通信
mori pane message "build done" --window orchestrator
mori pane id                                 # 打印当前面板标识
```

完整 CLI 规范请参阅 [docs/cli-redesign.md](docs/cli-redesign.md)。

## 终端配置

Mori 使用 Ghostty 的配置系统。在 `~/.config/ghostty/config` 中自定义终端。Mori 仅覆盖少量嵌入相关设置（无窗口装饰、关闭最后窗口不退出）。

## 键盘快捷键

完整列表请参阅 [docs/keymaps.zh-Hans.md](docs/keymaps.zh-Hans.md)。常用快捷键：

| 快捷键 | 操作 |
|---|---|
| <kbd>⌘</kbd>+<kbd>T</kbd> | 新建窗口（标签页） |
| <kbd>⌘</kbd>+<kbd>D</kbd> / <kbd>⌘</kbd>+<kbd>⇧</kbd>+<kbd>D</kbd> | 右分屏 / 下分屏 |
| <kbd>⌃</kbd>+<kbd>Tab</kbd> | 切换工作树 |
| <kbd>⌘</kbd>+<kbd>⇧</kbd>+<kbd>N</kbd> | 新建工作树 |
| <kbd>⌘</kbd>+<kbd>⇧</kbd>+<kbd>P</kbd> | 命令面板 |
| <kbd>⌘</kbd>+<kbd>G</kbd> | Lazygit |
| <kbd>⌘</kbd>+<kbd>E</kbd> | Yazi |

## 许可证

[MIT](LICENSE)
