<p align="center">
  <img src="assets/banner.svg" alt="Mori" width="600">
</p>

<p align="center">
  <a href="README.md">English</a> | <b>中文</b>
</p>

一款原生 macOS 工作区终端，围绕**项目**和**工作树**组织，由 **tmux** 和 **libghostty** 驱动。

Mori 不再让你管理零散的终端标签页，而是将 git 仓库视为一等公民。每个工作树（分支检出）都拥有独立的持久化 tmux 会话，支持多窗口和多窗格——通过原生侧边栏和 GPU 加速终端呈现。

## 为什么选择 Mori

- **项目优先导航** — 在仓库和分支间切换，而非匿名标签页
- **本地 + 远程项目** — 在同一个添加流程中支持本地目录与 SSH 远程仓库
- **持久化会话** — 关闭应用后重新打开，一切仍在 tmux 中运行
- **原生 macOS 体验** — 侧边栏、命令面板、通知、键盘快捷键
- **GPU 渲染终端** — libghostty（Ghostty 的渲染引擎）搭配 Metal 加速
- **工作树感知** — 同一仓库的多个分支可并行运行，各自拥有独立会话

## 工作原理

```
项目 (git 仓库)
  └─ 工作树 (分支检出)
       └─ tmux 会话
            ├─ 窗口 (标签页)  →  窗格
            ├─ 窗口           →  窗格 | 窗格
            └─ 窗口           →  窗格
```

每个工作树映射到一个 tmux 会话。窗口和窗格是标准的 tmux 概念。Mori 提供上层 UI——负责组织、导航和状态展示。

## 架构

```
应用 (AppKit 外壳 + SwiftUI 侧边栏视图)
  ├─ MoriCore         — 模型 + 可观察应用状态
  ├─ MoriUI           — SwiftUI 侧边栏视图
  ├─ MoriTmux         — tmux CLI 集成 (actor)
  ├─ MoriGit          — Git 工作树/状态发现 (actor)
  ├─ MoriTerminal     — libghostty 终端渲染
  ├─ MoriPersistence  — 基于 GRDB 的 SQLite 持久化
  └─ MoriIPC          — Unix socket IPC + `ws` CLI
```

## 系统要求

- macOS 14 (Sonoma) 或更高版本
- tmux
- [mise](https://mise.jdx.dev/)（任务运行器）
- Zig 0.15.2 + Xcode（用于构建 libghostty）

## 安装

### Homebrew

```bash
brew tap vaayne/tap
brew install --cask mori
```

### GitHub Releases

可从 [GitHub Releases](https://github.com/vaayne/mori/releases) 下载最新发布版本。

- `.dmg`：打开磁盘镜像后，将 `Mori.app` 拖入 `/Applications`
- `.zip`：解压压缩包后，将 `Mori.app` 移动到 `/Applications`

Homebrew tap 会安装 `Mori.app`。发布版应用包也会内置 `mori` CLI 以支持基于 Homebrew 的安装，且 cask 会声明 `tmux` 依赖。

## 构建与运行

```bash
mise run build           # Debug 构建
mise run build:release   # Release 构建
mise run dev             # 构建并运行
mise run test            # 运行所有测试
mise run clean           # 清理构建产物
```

libghostty XCFramework 需要先行构建：

```bash
mise run build:ghostty   # 需要 Zig 0.15.2 + Xcode
```

## CLI

`mori` 命令可以从终端与 Mori 交互：

```bash
mori project list
mori open /path/to/repo
mori worktree create <project> <branch>
mori focus <project> <worktree>
mori send <project> <worktree> <window> "command"
mori new-window <project> <worktree> <name>
```

## 终端配置

Mori 使用 Ghostty 的配置系统。在 `~/.config/ghostty/config` 中自定义终端。Mori 仅覆盖少量嵌入相关设置（无窗口装饰、关闭最后窗口不退出）。

## 键盘快捷键

完整列表请参阅 [docs/keymaps.zh-Hans.md](docs/keymaps.zh-Hans.md)。常用快捷键：

| 快捷键                                                        | 操作              |
| ------------------------------------------------------------ | ----------------- |
| <kbd>⌘</kbd>+<kbd>T</kbd>                                    | 新标签页 (tmux 窗口) |
| <kbd>⌘</kbd>+<kbd>W</kbd>                                    | 关闭窗格          |
| <kbd>⌘</kbd>+<kbd>D</kbd> / <kbd>⌘</kbd>+<kbd>⇧</kbd>+<kbd>D</kbd> | 右分屏 / 下分屏    |
| <kbd>⌘</kbd>+<kbd>1</kbd>–<kbd>⌘</kbd>+<kbd>9</kbd>          | 跳转到标签页 N     |
| <kbd>⌃</kbd>+<kbd>Tab</kbd> / <kbd>⌃</kbd>+<kbd>⇧</kbd>+<kbd>Tab</kbd> | 切换工作树         |
| <kbd>⌘</kbd>+<kbd>⇧</kbd>+<kbd>P</kbd>                       | 命令面板           |
| <kbd>⌘</kbd>+<kbd>B</kbd>                                    | 切换侧边栏         |
| <kbd>⌘</kbd>+<kbd>G</kbd>                                    | Lazygit            |
| <kbd>⌘</kbd>+<kbd>E</kbd>                                    | Yazi               |


## 许可证

[MIT](LICENSE)
