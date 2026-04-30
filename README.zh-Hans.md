<p align="center">
  <img src="assets/banner.svg" alt="Mori" width="600">
</p>

<p align="center">
  <a href="README.md">English</a> | <b>中文</b>
</p>

Mori 是给同时跑多个 git 分支的开发者做的 macOS 终端。不用再翻匿名标签页，也不用担心切换上下文时 tmux 状态丢掉——每个分支有自己的独立环境，侧边栏点一下就切过去。

## 截图

| 浅色 | 深色 | Lazygit | Yazi | 设置 |
|---|---|---|---|---|
| ![](docs/screenshots/light-mode.jpeg) | ![](docs/screenshots/dark-mode.jpeg) | ![](docs/screenshots/lazygit.png) | ![](docs/screenshots/yazi.jpeg) | ![](docs/screenshots/settings.jpeg) |

## 功能

- **侧边栏管所有分支** — 项目和工作树都在侧边栏，不用再找匿名标签页对应哪个分支
- **关掉再开，状态还在** — Mori 退出后 tmux 继续跑，第二天打开接着用
- **分支真正隔离** — 每个工作树有独立目录和 tmux 会话，`main` 和 `feat/auth` 同时跑互不影响
- **本地和 SSH 都支持** — 本地目录或远程服务器都能连，Mac 原生界面
- **GPU 渲染** — 用 Ghostty 的 libghostty 引擎，Metal 加速
- **CLI + 适合 Agent** — `mori` 命令行通过 Unix socket 控制一切，脚本和 AI Agent 工作流都好用
- **MoriRemote** — 不在 Mac 旁边时，用 iPhone/iPad 通过 SSH 连进来

## 工作原理

Mori 把开发的层级结构直接映射到 tmux：每个 git 工作树是一个 tmux 会话，会话里有窗口（标签页）和面板（分屏）。关掉 Mori，明天回来，里面跑的东西一个不少。

```
Project  项目（git 仓库）
└── Worktree  工作树（分支）       ← tmux 会话  例如 myapp/feat-auth
    ├── Window  窗口（标签页）     ← tmux 窗口  例如 "shell"
    │   ├── Pane  面板（左侧分屏） ← tmux 面板
    │   └── Pane  面板（右侧分屏） ← tmux 面板
    └── Window  窗口（标签页）     ← tmux 窗口  例如 "logs"
        └── Pane  面板
```

- **Project（项目）** — 一个 git 仓库，用根路径和短名称标识。
- **Worktree（工作树）** — `git worktree` 检出的分支目录，对应一个 tmux 会话（`<项目>/<分支>`）。
- **Window（窗口）** — 会话里的 tmux 窗口，就是标签页。
- **Pane（面板）** — 窗口里的 tmux 面板，就是分屏。

侧边栏列出所有项目和工作树，点一下就接上对应会话，切换是即时的。

## 安装

```bash
brew tap vaayne/tap
brew install --cask mori
```

也可以从 [GitHub Releases](https://github.com/vaayne/mori/releases) 下载。MoriRemote iOS 版在 [TestFlight](https://testflight.apple.com/join/k2GFJPC2)。

<details>
<summary>从源码编译</summary>

需要 macOS 14+、tmux、[mise](https://mise.jdx.dev/)、Zig 0.15.2 和 Xcode。

```bash
mise run build    # Debug 构建（自动拉取 libghostty）
mise run dev      # 构建并运行
mise run test     # 跑所有测试
```
</details>

## CLI

`mori` 命令行通过 Unix socket 跟应用通信，没开的话会自动启动。在 Mori 终端里用的话，`--project`、`--worktree` 这些参数可以省掉，Mori 会自动从环境变量读。

```bash
mori project open .                          # 把当前目录加为项目
mori worktree new feat/auth --project myapp  # 新建工作树，自动创建 tmux 会话
mori pane read --lines 100                   # 读取面板输出（Agent 常用）
mori focus --project myapp --worktree feat/auth  # 切换到指定工作树
```

所有命令加 `--json` 可以输出机器可读格式。完整文档见 [docs/cli-redesign.md](docs/cli-redesign.md)。

## 终端配置

Mori 用的是 Ghostty 那套配置，直接改 `~/.config/ghostty/config` 就行。Mori 只覆盖了几个嵌入相关的选项（去掉窗口装饰、最后一个窗口关掉不退出应用）。

Mori 管理的 tmux 会话默认会加一小段预设：开鼠标、关状态栏，方便快速上手。如果你已经有自己的 `tmux.conf`，在**设置 → Tools** 里关掉这个预设就好。

## 快捷键

完整列表见 [docs/keymaps.zh-Hans.md](docs/keymaps.zh-Hans.md)，常用的：

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
