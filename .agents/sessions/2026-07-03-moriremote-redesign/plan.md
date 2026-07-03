# MoriRemote 移动端 UI 重设计

日期: 2026-07-03 · 状态: 已评审现状(模拟器实机走查 + 代码阅读)

## 现状诊断(iPhone 17 Pro 模拟器,连接真实 MacMini)

1. **连接后直接甩进 tmux scrollback**。没有任何导向:不知道自己在哪个 session/window,
   更不知道各个 agent 在干嘛。手机上的核心场景是 triage(看状态 → 跳过去 → 回复 → 走人),
   不是打字,落地页答非所问。
2. **Sidebar sheet 信息架构失衡**。Server 卡片 + Switch Host/Disconnect 两个大按钮吃掉
   sheet 约 40% 高度,但它们是低频操作;窗口行显示 `[tmux]` + 路径,信息量近乎为零;
   agent 状态(working/waiting/done)只在多 pane 时以小字出现 —— 最有价值的信息最不可见。
3. **视觉层级脏**。4% 白色卡片 + 1px 描边无限嵌套(卡片套卡片套行),PROJECTS > main >
   MAIN 三层冗余标签;整体呈现"描边地狱"。
4. Key bar(esc/ctrl/tab/方向键/自定义)本身可用,不动。

## 数据前提(已确认)

- `ShellCoordinator` 每 5s 轮询 tmux,pane 级携带 `@mori-agent-state`(working/waiting/done)
  与 `@mori-agent-name`(claude/codex/…),见 ShellCoordinator.swift:447。
- Session 命名约定 `<project>/<branch>`,已有 projectGroups 分组逻辑(TmuxSidebarView.swift:80)。

## 设计原则

- **Agent-first triage**:首屏回答"我的 agent 现在什么状态、有没有在等我"。
- **状态必须可跳转**(见 memory: status-ui-must-be-actionable):任何状态指示点击后直达对应终端。
- 保持 Mori 暗色安静语言,复用/扩展 `Theme.swift` tokens,减少描边、用间距和字重分层。

## 方案

### A. Workspace 首页(compact 新落地页)

连接成功(state == .shell)后,compact 宽度落在 **Workspace 页**,不再直接进终端。
终端 PTY 照常在底层建立(轮询依赖它),这只是导航层的改变。

结构(NavigationStack push 终端):

- 顶部 inline bar:server 名 + 绿色连接点;右侧 `ellipsis` menu:Switch Host / Disconnect;
  右侧 `plus` menu:New Window / New Session。
- 按 project 分组(现有逻辑),组头 = project 名(小写 uppercase 小标)。
- Session 区块:branch 名(无 branch 用全名)+ attached 小点;区块内列 window 行。
- **Window 行(核心)**:
  - 主标题:agent 名(有 @mori-agent-name 时,如 "claude")否则 window name;
  - 状态 chip(行尾):working = accent 色点 + "Working"(点用 0.8s 呼吸动画),
    waiting = 橙色 "Needs input",done = 绿色 "Done",无 agent = 灰色 pane 命令名;
  - 副标题:shortPath(mono 小字);
  - 多 pane 窗口:行下缩进列 pane 子行,每行同样的 agent chip 规则;
  - 点击行/子行 → selectTmuxWindow / selectTmuxPane → push TerminalScreen。
- 状态聚合:window 内任一 pane waiting 则整行按 waiting 显示(waiting > working > done > none)。
- 空态:沿用现有"New Session"空态,视觉减负(去卡片描边)。
- 下拉刷新 → refreshTmuxState()。

### B. TerminalScreen(compact)

- 顶部加 slim bar(高约 44pt,terminalBg 上直接放,底部 1px divider):
  back chevron(回 Workspace,不断开)· 标题 = 当前 window 名(副标 session)·
  当前 window 的 agent 状态 chip · 右侧 tmux 快捷菜单按钮(现有 confirmationDialog)。
- Key bar 的 sidebar 按钮改为返回 Workspace(替代现在的 sheet);
  现有 TmuxSidebarView sheet 在 compact 下移除。
- 断开/切主机入口保留在 Workspace 顶部 menu 与 key bar ellipsis menu(现有)。

### C. iPad regular 宽度

- 持久侧栏内容替换为新的 Workspace 列表组件(同一 SwiftUI 视图,数据+回调参数化,
  遵守"SwiftUI views are pure"约定);Server 卡片砍掉,换成顶部 server bar。
- 分栏结构、宽度、reveal 按钮不动。

### D. 视觉 pass

- 去嵌套卡片:session 区块用平面分组(组头小标 + 行),行仅在选中/高亮时上底色;
  全局描边只保留在交互控件(按钮、chip)。
- ServerListView:行距/空态微调,统一新 chip 语言;不改流程。
- Theme.swift 增加:`agentWorking`(= accent)、`agentWaiting`(橙)、`agentDone`(绿)、
  chip 字体/内边距 tokens。

## 非目标

- 不动 SSH/tmux 协议层与轮询逻辑(除新增只读的状态聚合 helper)。
- 不动 KeyBar 按键布局与自定义机制。
- 不做 iOS 浅色主题、不加依赖、不改 TestFlight 版本号(保持 0.3.5)。

## 验收

1. `xcodebuild -project MoriRemote/MoriRemote.xcodeproj -scheme MoriRemote -destination 'platform=iOS Simulator,…' build` 通过。
2. 模拟器走查:connect → Workspace(agent 状态可见)→ 点 window 进终端 → back 回 Workspace
   → 切另一 window → key bar 正常。
3. 新增用户可见字符串全部 `.localized()` 且 en + zh-Hans 双份。
4. CHANGELOG.md / CHANGELOG.zh-Hans.md 各加 Unreleased 条目。

---

# 二轮:Hosts 管理 / 终端内切换 / 文字选择

日期: 2026-07-03 · 前提: 一轮 Workspace 重设计已落地(工作区未 commit)

## E. Hosts 列表与管理(ServerListView / ServerFormView)

- Server 行增加 swipe actions:右滑 Edit(accent)、左滑 Delete(destructive,沿用确认弹窗);
  现有 `…` menu 与 context menu 保留。
- `Server` 模型加可选 `lastConnectedAt: Date?`(JSON 持久化,旧数据缺字段容错为 nil);
  连接成功(进入 .shell)时更新;列表按 lastConnectedAt 降序排(nil 排最后,同为 nil 按现有顺序)。
- 行副标题:`user@host` 后追加 ` · <defaultSession>`(mono 小字,现有字体)。
- 非目标:SSH key 认证(牵动 MoriSSH,单独立项)。

## F. 终端内快速切换(TerminalScreen compact)

- **Window chips 条**:compact 顶栏下方新增高约 34pt 的横向滚动 chips 行,列当前 active session
  的所有 windows:chip = 状态点(agent 聚合色,working 呼吸)+ window 名(agent 名优先,同 Workspace 行标题规则);
  当前 window 高亮(accentSoft 底 + accent 描边)。点击 → selectTmuxWindow。
  仅当 windows.count > 1 时显示该行。
- **Workspace sheet 快速切换**:key bar 的 sidebar 按钮从"pop 回首页"改回"打开 sheet":
  present 半屏 sheet(medium/large detents),内容复用 WorkspaceView(overlay 模式,showsDismissButton: true,
  选中 window/pane 后自动 dismiss,不退导航栈)。顶栏 back chevron 仍是回 Workspace 首页。
  一轮里 TerminalScreen compact 移除的 sheet 逻辑按此恢复(用新 WorkspaceView,并接上二轮的全部回调:
  rename/kill/close 等)。sheet 里的 onSwitchHost/onDisconnect 沿用现有回调。
- 顶栏标题点击 = 同 sidebar 按钮(打开 sheet)。

## G. 文字选择(零 Packages 改动)

- Key bar 尾部(键盘收起键旁)新增**选择模式**切换键:icon `text.cursor`(或 `selection.pin.in.out`),
  toggle `terminalView.allowMouseReporting`(SwiftTerm public 属性,经 renderer.swiftTermView 已可达;
  KeyBarView 已持有 terminalView 弱引用)。
  - active 样式与 ctrl toggle 一致(accent 底色);
  - active 时长按/拖动 = SwiftTerm 原生选择 + iOS copy 菜单,tmux 收不到鼠标事件;
  - 切换回时恢复 mouse reporting。
  - 状态不持久化,断开/切主机时重置为 reporting on。
- 该键为固定键(与 keyboard dismiss 同级),不进自定义 layout。

## 验收(二轮)

1. Debug 构建通过。
2. 模拟器:server 行 swipe 出现 Edit/Delete;连接后 chips 条正确高亮并可切换(单 window 时不显示);
   key bar sidebar 键弹出 workspace sheet,选择后 dismiss 并切换;选择模式键切换后长按可出 copy 菜单。
3. 新字符串双语;CHANGELOG 双语在一轮条目上扩写或新增条目。

---

# 三轮:窗口标题 "[tmux]" 修复

根因:tmux 默认 `automatic-rename-format` = `#{?pane_in_mode,[tmux],#{pane_current_command}}`,
pane 处于 copy-mode 时窗口名变成 "[tmux]"。app 直接信任 window.name,
多个窗口滚动过 scrollback 后 chips / 行标题全是 "[tmux]",无法区分。

修复(纯展示层,不动主机 tmux 配置):`TmuxWindow.workspaceTitle` 优先级改为
agent 名 → window.name(非空且 != "[tmux]")→ fallbackCommand → 原始 name。
`TerminalScreen.compactTopBar` 标题从 `currentWindow?.name` 改用 `workspaceTitle`。
不加新字符串、不加 CHANGELOG(修的是未发布功能)。
