<p align="center">
  <img src="assets/banner.svg" alt="Mori" width="600">
</p>

<p align="center">
  <a href="README.md">English</a> | <b>中文</b>
</p>

一款原生 macOS 工作区终端，围绕**项目**和**工作树**组织，由 **tmux** 和 **libghostty** 驱动。

Mori 将 git 仓库视为一等公民。每个工作树都拥有独立的持久化 tmux 会话，通过原生侧边栏和 GPU 加速终端呈现。

## 功能特性

- **项目优先导航** — 在仓库和分支间切换，而非匿名标签页
- **持久化会话** — 关闭应用后重新打开，tmux 保持一切运行
- **工作树感知** — 同一仓库的多个分支并行运行
- **本地 + SSH 项目** — 在同一流程中添加本地文件夹或远程仓库
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

```bash
mori project list
mori open /path/to/repo
mori worktree create <project> <branch>
mori focus <project> <worktree>
mori new-window <project> <worktree> <name>
mori send <project> <worktree> <window> "keys"
mori pane list|read|message|id
```

## 终端配置

Mori 使用 Ghostty 的配置系统。在 `~/.config/ghostty/config` 中自定义终端。Mori 仅覆盖少量嵌入相关设置（无窗口装饰、关闭最后窗口不退出）。

## 键盘快捷键

完整列表请参阅 [docs/keymaps.zh-Hans.md](docs/keymaps.zh-Hans.md)。常用快捷键：

| 快捷键 | 操作 |
|---|---|
| <kbd>⌘</kbd>+<kbd>T</kbd> | 新标签页 |
| <kbd>⌘</kbd>+<kbd>D</kbd> / <kbd>⌘</kbd>+<kbd>⇧</kbd>+<kbd>D</kbd> | 右分屏 / 下分屏 |
| <kbd>⌃</kbd>+<kbd>Tab</kbd> | 切换工作树 |
| <kbd>⌘</kbd>+<kbd>⇧</kbd>+<kbd>N</kbd> | 新建工作树 |
| <kbd>⌘</kbd>+<kbd>⇧</kbd>+<kbd>P</kbd> | 命令面板 |
| <kbd>⌘</kbd>+<kbd>G</kbd> | Lazygit |
| <kbd>⌘</kbd>+<kbd>E</kbd> | Yazi |

## 许可证

[MIT](LICENSE)
