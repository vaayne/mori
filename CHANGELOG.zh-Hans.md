# 更新日志

本文件记录项目的所有重要变更。

格式基于 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)，
版本号遵循[语义化版本](https://semver.org/spec/v2.0.0.html)规范。

## [Unreleased]

## [0.3.6] - 2026-04-13

### ✨ 新功能

- 侧边栏项目支持拖拽排序 ([#64](https://github.com/vaayne/mori/pull/64))
- 工具栏和侧边栏底部按钮长按 Cmd 显示快捷键提示 ([#63](https://github.com/vaayne/mori/pull/63))

### 🐛 问题修复

- 修复 MoriRemote 快捷键栏手势识别器崩溃 ([#62](https://github.com/vaayne/mori/pull/62))
- 移除多余的 PreToolUse 代理钩子以减少日志干扰 ([#65](https://github.com/vaayne/mori/pull/65))

**完整变更记录**: [v0.3.5...v0.3.6](https://github.com/vaayne/mori/compare/v0.3.5...v0.3.6)

## [0.1.0] - 2026-03-20

Mori 首次发布——一款原生 macOS 工作区终端，围绕项目、工作树和 tmux 会话组织。

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

**完整变更日志**：[v0.1.0](https://github.com/vaayne/mori/commits/v0.1.0)

[Unreleased]: https://github.com/vaayne/mori/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/vaayne/mori/releases/tag/v0.1.0
