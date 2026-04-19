# 更新日志

本文件记录项目的所有重要变更。

格式基于 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)，
版本号遵循[语义化版本](https://semver.org/spec/v2.0.0.html)规范。

## [Unreleased]

### ✨ 新功能

- 在设置 → Tools 中新增可切换的 Mori tmux 默认预设，让 Mori 管理的会话默认开启鼠标支持并隐藏 tmux 状态栏，同时也允许用户一键回退到自己 `tmux.conf` 中的鼠标与状态栏行为

### 🐛 问题修复

- 终端字体选择器现在会包含 JetBrains Maple Mono 这类系统字体：当 AppKit 没有将其标记为等宽字体时，改为回退到统一字形宽度检测来识别
- 安装 Agent Hook 时保留软链接的 agent 配置文件（例如指向 dotfiles 仓库的 `~/.claude/settings.json`）：原子写入现在会先解析软链接目标，避免链接被替换为普通文件 ([#80](https://github.com/vaayne/mori/issues/80))

## [0.4.0] - 2026-04-18

### 🎨 界面优化

- **侧边栏精修** — 更安静的状态条，右对齐显示工作树数量；为每个项目加入彩色字母图块，便于一眼扫读；当前选中的工作树行新增左侧强调条与柔和的渐变背景 ([#77](https://github.com/vaayne/mori/pull/77))

**完整变更记录**: [v0.3.8...v0.4.0](https://github.com/vaayne/mori/compare/v0.3.8...v0.4.0)

## [0.3.8] - 2026-04-17

### ✨ 新功能

- **应用图标焕新** — 用更贴近终端气质的 Mori 新标记替换原来的风景吉祥物 Dock 图标：更简化的树桩轮廓、刻入式提示符图形，以及更适合 macOS 的构图
- **CLI 重设计：上下文感知寻址** — 所有地址组件（`--project`、`--worktree`、`--window`、`--pane`）现为可选标志，默认读取对应的 `MORI_*` 环境变量，在 Mori 终端内无需重复输入
- **新增 `mori window` 命令组** — `window list`、`window new`、`window rename`、`window close`
- **新增 `mori worktree list` 和 `worktree delete`** — 列出项目的所有工作树；删除工作树（终止 tmux 会话并移除 git 工作树）
- **新增面板子命令** — `pane new`（分割）、`pane send`、`pane rename`、`pane close`，替代原有的顶层 `send` 和 `new-window` 命令
- **`mori focus` 增强** — 新增 `--window` 参数，可聚焦到指定窗口
- **`pane list` 范围优化** — 新增 `--window` 过滤；在 Mori 终端内默认范围为当前窗口

### 🗑️ 破坏性变更

- 移除顶层 `mori send`、`mori new-window` 及位置参数形式的 `mori focus`，分别由 `mori pane send`、`mori window new` 和基于标志的 `mori focus` 替代

**完整变更记录**: [v0.3.7...v0.3.8](https://github.com/vaayne/mori/compare/v0.3.7...v0.3.8)

## [0.3.7] - 2026-04-16

### ✨ 新功能

- 支持置顶项目到侧边栏顶部，可通过右键菜单或拖拽操作 ([#74](https://github.com/vaayne/mori/pull/74))

### 🐛 问题修复

- 修复 MoriRemote 快捷键栏触摸从按钮开始时无法水平滚动的问题 ([#69](https://github.com/vaayne/mori/pull/69))
- 对新创建的会话应用 `tmux status off` ([#67](https://github.com/vaayne/mori/pull/67))

**完整变更记录**: [v0.3.6...v0.3.7](https://github.com/vaayne/mori/compare/v0.3.6...v0.3.7)

## [0.3.6] - 2026-04-13

### ✨ 新功能

- 侧边栏项目支持拖拽排序 ([#64](https://github.com/vaayne/mori/pull/64))
- 工具栏和侧边栏底部按钮长按 Cmd 显示快捷键提示 ([#63](https://github.com/vaayne/mori/pull/63))

### 🐛 问题修复

- 修复 MoriRemote 快捷键栏手势识别器崩溃 ([#62](https://github.com/vaayne/mori/pull/62))
- 移除多余的 PreToolUse 代理钩子以减少日志干扰 ([#65](https://github.com/vaayne/mori/pull/65))

**完整变更记录**: [v0.3.5...v0.3.6](https://github.com/vaayne/mori/compare/v0.3.5...v0.3.6)

## [0.3.5] - 2026-04-13

### ✨ 新功能

- **MoriRemote**：添加自适应 iPad 布局，断开连接时支持分屏服务器浏览，连接后保持双窗格工作区 ([#60](https://github.com/vaayne/mori/pull/60))
- **MoriRemote**：优化 iPhone 和 iPad UI，遵循 Mac 优先的 `DESIGN.md` 设计语言，更紧凑的服务器行、更扁平的 tmux 侧边栏、更紧凑的终端边框，以及规范化的深色语义样式 ([#60](https://github.com/vaayne/mori/pull/60))
- **MoriRemote**：重新设计终端配件栏和按键自定义面板，使用紧凑的 Mori 令牌、语义化强调色和本地化的 tmux 操作 ([#60](https://github.com/vaayne/mori/pull/60))
- **MoriRemote**：优化终端连接微状态，提供更丰富的 iPad 连接/失败详情状态和更平静的终端内 shell 准备覆盖层 ([#60](https://github.com/vaayne/mori/pull/60))
- 开始用共享的窗口内伴侣工具面板替换 Yazi/Lazygit 的独立 tmux 窗口流程，右侧分割用于文件和 Git ([#58](https://github.com/vaayne/mori/pull/58))

### 🐛 问题修复

- **MoriRemote**：使常规宽度终端侧边栏再次可折叠，并用稳定的确认对话框替换崩溃的 iPad 键盘配件 tmux 菜单 ([#60](https://github.com/vaayne/mori/pull/60))
- **MoriRemote**：将紧凑终端导航移至配件行，在 tmux 旁添加返回控制，保持终端视口无额外边框 ([#60](https://github.com/vaayne/mori/pull/60))
- **MoriRemote**：加固终端会话生命周期处理，防止断开连接、主机切换、过时 shell 回调和配件栏重用导致的竞态进入损坏的 shell/tmux 状态 ([#60](https://github.com/vaayne/mori/pull/60))
- **MoriRemote**：延迟配件栏导航和 tmux/自定义展示直到键盘响应者周期之后，防止点击返回或 tmux 操作时崩溃 ([#60](https://github.com/vaayne/mori/pull/60))
- **MoriRemote**：通过防止过时的断开任务覆盖较新的 SSH 连接尝试，保持返回/断开后的重新连接可靠性 ([#60](https://github.com/vaayne/mori/pull/60))
- **MoriRemote**：通过将缺失密码和 SSH 超时失败显示为显式错误，阻止服务器列表永远卡在"连接中…" ([#60](https://github.com/vaayne/mori/pull/60))
- 为 tmux、Lazygit 和 Yazi 添加共享工具路径解析，包括自定义安装前缀如 `~/homebrew/bin`、显式设置覆盖和本地启动路径 ([#59](https://github.com/vaayne/mori/pull/59))

### ♻️ 重构

- 统一侧边栏重新设计后移除遗留的工作流状态和侧边栏模式代码路径，包括 `mori status` CLI 命令和手动侧边栏状态控制 ([#57](https://github.com/vaayne/mori/pull/57))

**完整变更记录**: [v0.3.4...v0.3.5](https://github.com/vaayne/mori/compare/v0.3.4...v0.3.5)

## [0.3.4] - 2026-04-12

### ✨ 新功能

- Ghostty 透明度继承：Mori 现在读取并持久化 `background-blur` 和 `background-opacity-cells`，将 Ghostty 窗口透明度/模糊应用到主工作区窗口，在设置中公开透明度控制，避免禁用单元格透明度时的强制不透明背景，添加 macOS 26 玻璃背景美化，并避免冗余的 tmux 主题重新应用 ([#55](https://github.com/vaayne/mori/pull/55))
- 添加 Droid 代理状态钩子支持，用于 Mori 中更丰富的代理生命周期跟踪 ([#53](https://github.com/vaayne/mori/pull/53))
- 引入统一侧边栏重新设计，实现任务/工作区对等，默认折叠非活动任务组，共享底部清理和改进的视觉层次 ([#56](https://github.com/vaayne/mori/pull/56))

### 🐛 问题修复

- 解决从打包的 `.app` 包内运行 `mori` 时的 CLI/app IPC 套接字路径不匹配 ([#52](https://github.com/vaayne/mori/pull/52))
- 依赖设置期间本地 Zig 链接器失败时回退到 CI GhosttyKit 产物
- 修复 MoriRemote 键盘输入被软键盘遮挡的问题并添加关闭按钮
- CI 中 iOS TestFlight 构建号默认使用 UTC 时间戳以避免重复构建号失败

**完整变更记录**: [v0.3.3...v0.3.4](https://github.com/vaayne/mori/compare/v0.3.3...v0.3.4)

## [0.3.3] - 2026-04-05

### ✨ 新功能

- 长按 Cmd 快捷键提示和上下文感知的 ⌘1-9 快速跳转 ([#49](https://github.com/vaayne/mori/pull/49))
- 侧边栏重新设计 — 间距、排版和视觉层次 ([#50](https://github.com/vaayne/mori/pull/50))

**完整变更记录**: [v0.3.2...v0.3.3](https://github.com/vaayne/mori/compare/v0.3.2...v0.3.3)

## [0.3.2] - 2026-04-03

### ✨ 新功能

- 在应用菜单中添加"远程连接"菜单项用于快速远程主机访问
- 从侧边栏上下文菜单添加项目重命名
- 跳过非 git 目录的 git 轮询，显示主页图标并展示工具安装提示
- 通过默认 Home 工作空间和工具检测改进引导体验

### 🐛 问题修复

- 非 git 目录不再显示"main"分支；去重工作树行

### ♻️ 重构

- 打开项目现在直接进入文件夹选择器（跳过中间对话框）

**完整变更记录**: [v0.3.1...v0.3.2](https://github.com/vaayne/mori/compare/v0.3.1...v0.3.2)

## [0.3.1] - 2026-04-03

### 📝 文档

- 添加实用的 GitHub 问题模板用于错误报告和功能请求

**完整变更记录**: [v0.3.0...v0.3.1](https://github.com/vaayne/mori/compare/v0.3.0...v0.3.1)

## [0.3.0] - 2026-04-02

### ✨ 新功能

- **可自定义键盘快捷键**：通过设置 > 键盘重新映射、取消分配或重置所有 Mori 应用快捷键 ([#37](https://github.com/vaayne/mori/pull/37))
- 快捷键冲突检测，锁定系统快捷键（阻止）和可配置快捷键（警告并覆盖选项）
- 稀疏 JSON 持久化用于键盘快捷键覆盖 (`keybindings.json`)
- **命令面板 + Cmd+P 项目切换器的模糊搜索** ([#34](https://github.com/vaayne/mori/pull/34), [#35](https://github.com/vaayne/mori/pull/35), [#38](https://github.com/vaayne/mori/pull/38))

### 🐛 问题修复

- 使代理桥接感知窗格
- 在标题栏右上角显示更新状态标签

**完整变更记录**: [v0.2.2...v0.3.0](https://github.com/vaayne/mori/compare/v0.2.2...v0.3.0)

## [0.2.2] - 2026-03-31

### 🐛 问题修复

- 修复"检查更新"无响应 — Sparkle 2.9 拒绝 `Contents/XPCServices/` 和 `Sparkle.framework` 内的重复 XPC 服务，导致 `SPUUpdater.start()` 静默失败

**完整变更记录**: [v0.2.1...v0.2.2](https://github.com/vaayne/mori/compare/v0.2.1...v0.2.2)

## [0.2.1] - 2026-03-31

### ✨ 新功能

- **MoriRemote**：用于远程访问的 iOS 应用，支持 SSH 终端 ([#30](https://github.com/vaayne/mori/pull/30))

### 🐛 问题修复

- 通过将 `UNUserNotificationCenter` API 从完成处理程序切换到 async/await，修复 `NotificationManager` 中的主线程断言崩溃

### 📦 依赖

- 将 `actions/checkout` 从 v5 升级到 v6
- 将 `upload-artifact` 和 `download-artifact` 从 v5 升级到 v7 以支持 Node.js 24

**完整变更记录**: [v0.2.0...v0.2.1](https://github.com/vaayne/mori/compare/v0.2.0...v0.2.1)

## [0.2.0] - 2026-03-31

### ✨ 新功能

- **代理桥接**：跨窗格代理监控、通信和仪表板 ([#31](https://github.com/vaayne/mori/pull/31))
  - `mori pane list` — 列出所有窗格及其项目/工作树/窗口/代理/状态信息
  - `mori pane read <project> <worktree> <window> [--lines N]` — 捕获窗格输出
  - `mori pane message <project> <worktree> <window> <text>` — 发送带发送者元数据的消息
  - `mori pane id` — 打印当前窗格身份用于自标记
  - 悬停任何带代理徽章的窗口行 → 弹出窗口显示窗格输出的最后几行
  - 点击等待徽章 → 内联回复字段 → 发送按键到窗格
  - 新的"代理"侧边栏模式按状态（需要注意、运行中、已完成、空闲）分组所有代理窗口
  - 多窗格仪表板面板（⌘⇧A）显示所有代理窗格的实时输出
  - 代理到代理消息协议，使用 `[mori-bridge from:...]` 信封格式
- 添加"等待中"代理状态用于快速回复支持

### 🐛 问题修复

- 在 tmux 会话命名中规范化项目 shortName ([#28](https://github.com/vaayne/mori/pull/28))
- 防止悬停预览在点击切换时触发
- 从应用层连接 `onRequestPaneOutput` 和 `onSendKeys` 回调

### ⚡ 性能

- 更快的悬停预览 — 立即显示弹出窗口并带加载旋转器

### 📝 文档

- 用全面指南重写 agent-bridge.md
- 添加预推送 CI 验证步骤到 AGENTS.md

**完整变更记录**: [v0.1.3...v0.2.0](https://github.com/vaayne/mori/compare/v0.1.3...v0.2.0)

## [0.1.3] - 2026-03-28

### ✨ 新功能

- **Sparkle 自动更新**：通过 Sparkle 2 框架进行应用内更新检查和安装 ([#25](https://github.com/vaayne/mori/pull/25))
  - 标题栏标签徽章显示更新状态（检查中、可用、下载中、安装中）
  - 弹出窗口显示版本详情、发布说明链接和安装/跳过/稍后操作
  - "检查更新..."菜单项和命令面板操作
  - CI 管道生成签名的 appcast.xml 并发布到 GitHub Pages
  - 完整的本地化支持（英文 + 简体中文）

- **任务模式侧边栏**：按工作流状态（待办、进行中、需要审核、已完成、已取消）而非项目层次结构分组所有跨项目工作树的替代侧边栏视图 ([#14](https://github.com/vaayne/mori/issues/14))
  - 通过侧边栏顶部的分段控制在任务和工作区视图之间切换
  - 通过上下文菜单、命令面板或 `mori status` CLI 命令手动更改状态
  - 首次 git 活动或代理使用时自动从待办过渡到进行中
  - 默认隐藏已取消项目并带显示切换；已完成组默认折叠
  - 跨项目工作树选择自动同步项目上下文
  - 完整的本地化支持（英文 + 简体中文）

- 添加项目现在提示选择`本地文件夹`或`远程项目 (SSH)` ([#24](https://github.com/vaayne/mori/pull/24))
- 添加 SSH 支持的远程项目支持，使 git/tmux 操作可在远程主机上运行，同时保持 Mori UI 本地
- 添加 VS Code 风格的顶部输入向导用于远程主机连接（`[user@]host[:port]`、认证模式、路径）
- 添加命令面板操作`远程：连接到主机...`
- 远程添加现在允许非 git 目录（git 集成是尽力而为，tmux 工作流仍然有效）
- 远程连接现在检测活动的 tmux 会话并允许将项目附加到现有会话，使侧边栏标签页/窗格反映该实时工作空间
- 添加 `MoriRemote` iOS 实验应用目标，通过 SSH 连接，附加到 tmux 控制模式，用 Ghostty 渲染窗格输出，并通过 tmux 发送键盘输入

### 🐛 问题修复

- `mise run build`/`build:release` 现在通过 `build:ghostty` 自动引导 GhosttyKit 以避免新鲜克隆上的缺失 XCFramework 错误
- `scripts/build-ghostty.sh` 现在验证 XCFramework 内容并在产物无效时重建，而不是将空目录视为有效
- `scripts/build-ghostty.sh` 现在当 `xcrun metal` 不可用时自动安装 Metal 工具链
- 设置`打开配置`现在强制文本编辑器打开并规范化配置文件权限为非可执行
- 远程终端附加现在重用 SSH 控制选项以获得更可靠的远程 tmux 会话处理
- 密码认证 SSH 项目现在将凭证持久化到 macOS 钥匙串并在应用重启后自动重新认证
- 终端表面缓存现在按端点命名空间，使本地和远程会话具有相同 tmux 名称时不再冲突
- `mori send` / `mori new-window` 现在路由到所选工作树的端点后端并使用原始 tmux 目标 ID
- 持久化的所选窗口 ID 现在从遗留原始 tmux ID（如 `@1`）迁移到端点命名空间 ID
- 远程 tmux 命令现在扩充 PATH（`/opt/homebrew/bin`、`/usr/local/bin`）以支持非默认远程安装
- 在项目菜单中添加`更新远程凭证…`操作，无需重新添加项目即可更正 SSH 认证
- 工作树会话现在保持每个分支至少一个 tmux 窗口/窗格，没有 `tmuxSessionName` 的遗留工作树自动回填
- 远程会话确保/创建/分割现在显示显式的"tmux 不可用"错误，并在会话引导失败时避免保持过时的终端附加
- 远程 tmux 命令 PATH 引导现在包括标准 Linux/macOS 系统路径，减少非登录 SSH shell 的假阴性
- Ghostty 表面关闭事件现在触发自动会话恢复，使"进程已退出"的远程终端重新连接而不是卡住
- 窗口关闭安全现在检查实时 tmux 会话窗口计数（不仅缓存的侧边栏状态）以避免意外杀死最后一个远程窗口/会话的竞态
- 远程终端现在执行自动重新连接重试，并带有专用的"重新连接会话"状态，以在瞬态 SSH 断开时提供类似 mosh 的连续性体验
- 远程会话发现/确保现在使用轻量级 tmux 查询（`list-sessions` / 目标 `list-windows`）而不是深度完整树扫描，防止来自无关窗格/窗口扫描错误的假"无会话"失败
- 远程终端 SSH 附加现在为交互式表面强制 `BatchMode=no`，使密码认证会话可以在没有控制主控活动时恢复而不是立即退出
- 运行时窗口索引现在安全地容忍重复窗口 ID 并去重冲突，防止来自过时重叠会话映射的启动/IPC 崩溃
- 启动现在自动规范化每个端点的冲突 tmux 会话绑定，远程附加现在阻止绑定已被另一个工作空间使用的会话
- SSH 密码引导不再将密钥注入继承的进程环境；askpass 现在使用最小环境并安全地设置临时脚本权限
- SSH 控制套接字路径现在使用固定长度的哈希名称和 `/tmp` 回退以避免 macOS Unix 套接字长度失败
- 远程 SSH 命令路径现在包括服务器 keepalive 选项和硬执行超时以防止挂起的 git/tmux 调用
- 钥匙串凭证读取失败现在向用户显示可操作的警报，而不是静默回退为"未找到密码"
- Ghostty 配置保存现在通过依赖 `ensureConfigFileExists()` 避免冗余目录创建
- 为共享 SSH 助手行为添加单元测试（控制路径长度、选项过滤、shell 转义、askpass 环境加固）
- Mori 应用终止现在同步移除 IPC 套接字，`mori` CLI 现在直接报告缺失或过时的应用套接字而不是超时 ([#23](https://github.com/vaayne/mori/pull/23))
- 从应用包内调用时 CLI 不再崩溃 — 安全的多路径资源包查找替换容易 fatalError 的 `Bundle.module`

### 📦 依赖

- 将 ghostty 子模块更新到 6057f8d2b

**完整变更记录**: [v0.1.2...v0.1.3](https://github.com/vaayne/mori/compare/v0.1.2...v0.1.3)

## [0.1.2] - 2026-03-27

### ✨ 新功能

- 发布应用包现在嵌入 `mori` CLI 以支持 Homebrew cask 安装

### 🐛 问题修复

- 标记的发布现在用实际发布版本而不是硬编码应用版本标记 Mori.app

### 📝 文档

- 在英文和中文 README 中添加 Homebrew tap 安装说明

### 🔧 CI/CD

- 发布自动化现在在发布标记发布后更新 `vaayne/homebrew-tap` 并更新新的 Homebrew cask 版本和 SHA-256

**完整变更记录**: [v0.1.1...v0.1.2](https://github.com/vaayne/mori/compare/v0.1.1...v0.1.2)

## [0.1.1] - 2026-03-27

### ✨ 新功能

- 任务模式侧边栏按工作流状态分组工作树，支持手动状态更改，并在以任务为中心的导航中保持项目选择同步
- 工作树创建现在使用专用面板，支持本地和远程分支发现
- 侧边栏工作树行现在显示上游状态、相对活动时间和更丰富的 git 状态信息
- 网络代理设置可从应用应用到 tmux 会话
- macOS 发布构建现在以签名、公证的应用归档加 DMG 安装程序形式发布

### 🐛 问题修复

- 打包的 `.app` 包现在正确从应用包加载 SwiftPM 资源，并使用解析的绝对二进制路径启动 tmux
- 发布归档现在避免 AppleDouble `._` 文件跨复制、zip 和解压流程，使签名在下载后保持有效
- 发布工作流环境处理和签名/公证步骤已修复用于 CI 构建
- 任务侧边栏和 tmux 集成收到关于命名、会话主题应用和启动行为的后续修复

### 📝 文档

- 添加代码签名、网络代理和工作树指南
- 更新 README、快捷键映射和发布相关文档以匹配当前应用行为

### 🔧 CI/CD

- 发布自动化现在构建签名和公证归档并发布 DMG 产物

**完整变更记录**: [v0.1.0...v0.1.1](https://github.com/vaayne/mori/compare/v0.1.0...v0.1.1)

## [0.1.0] - 2026-03-20

Mori 首次发布 —— 一款原生 macOS 工作区终端，围绕项目、工作树和 tmux 会话组织。

### ✨ 新功能

- 三栏式 UI：项目栏、工作树侧边栏、终端区域（AppKit + SwiftUI）
- libghostty GPU 加速终端渲染（Metal），完全兼容 ghostty 配置
- tmux 作为持久化运行时后端，5 秒协调轮询
- 项目和工作树管理（添加/移除项目，创建/移除工作树）
- 会话模板，自动创建窗口（shell/run/logs）
- Git 状态轮询，侧边栏徽章显示（dirty、unread、代理状态）
- 命令面板，支持模糊搜索（Cmd+Shift+P）
- 代理感知标签页，基于钩子的状态检测，支持 Claude Code、Codex CLI 和 Pi（[#4](https://github.com/vaayne/mori/pull/4)）
- macOS 通知和 Dock 徽章，用于未读/代理活动提醒
- 通过 Unix socket 的 IPC，`mori` CLI 提供 6 个子命令
- 自动化钩子系统（每个项目的 `.mori/hooks.json`）
- 对齐 Ghostty 的快捷键设计（分屏、标签页、窗格导航）
- 可调整大小的侧边栏，支持拖拽分隔线
- 窗口大小跨启动持久化
- 打包后自动安装到 /Applications

### 🐛 问题修复

- 将 tmux 主题选项限定为 Mori 管理的会话（[#6](https://github.com/vaayne/mori/pull/6)）
- Swift 6 并发修复（SIGTRAP 崩溃、PTYTerminalView deinit）
- 健壮的快捷键处理，菜单优先 + ghostty action 回调
- 上下文感知的空状态，支持断开会话的重新连接
- .app 环境下通过交互式登录 shell 解析 PATH

### ♻️ 重构

- 用 JSON 文件持久化替换 GRDB/SQLite（[#5](https://github.com/vaayne/mori/pull/5)）
- 从 SwiftTerm 迁移到 libghostty 终端后端
- 将 `ws` CLI 更名为 `mori`
- Ghostty 子模块，为 .app 构建打包主题

### 📝 文档

- README 包含横幅、中文翻译和快捷键参考
- CLAUDE.md 包含架构指南和构建命令
- Agent Hooks 用户指南（`docs/agent-hooks.md`）

### 🔧 CI/CD

- GitHub Actions 工作流，用于 CI 构建和发布
- GhosttyKit XCFramework 构建基础设施

**完整变更记录**: [v0.1.0](https://github.com/vaayne/mori/commits/v0.1.0)

[Unreleased]: https://github.com/vaayne/mori/compare/v0.3.7...HEAD
[0.3.7]: https://github.com/vaayne/mori/compare/v0.3.6...v0.3.7
[0.3.6]: https://github.com/vaayne/mori/compare/v0.3.5...v0.3.6
[0.3.5]: https://github.com/vaayne/mori/compare/v0.3.4...v0.3.5
[0.3.4]: https://github.com/vaayne/mori/compare/v0.3.3...v0.3.4
[0.3.3]: https://github.com/vaayne/mori/compare/v0.3.2...v0.3.3
[0.3.2]: https://github.com/vaayne/mori/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/vaayne/mori/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/vaayne/mori/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/vaayne/mori/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/vaayne/mori/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/vaayne/mori/compare/v0.1.3...v0.2.0
[0.1.3]: https://github.com/vaayne/mori/releases/tag/v0.1.3
[0.1.2]: https://github.com/vaayne/mori/releases/tag/v0.1.2
[0.1.1]: https://github.com/vaayne/mori/releases/tag/v0.1.1
[0.1.0]: https://github.com/vaayne/mori/releases/tag/v0.1.0
