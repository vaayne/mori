# 更新日志

本文件记录项目的所有重要变更。

格式基于 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)，
版本号遵循[语义化版本](https://semver.org/spec/v2.0.0.html)规范。

## [Unreleased]

## [0.6.3] - 2026-07-24

### 🐛 问题修复

- **macOS**：侧栏与伴侣面板的分割线重新可以拖拽调整宽度。此前拖拽命中区被两侧视图吞掉（实际只能点中 1 像素的线），且侧栏宽度被限制在 220–260pt。现在每条分割线有专属的 8pt 拖拽区，悬停和拖拽时显示强调色高亮条，侧栏最宽可达 400pt。

### 🎨 界面优化

- **macOS**：命令面板与新建工作区面板合并为统一的 Command Panel——同一个浮动面板，共享材质、圆角、搜索框和列表样式，并跟随 Ghostty 主题。在命令面板里选择**新建 Worktree**时，工作区选择器直接在面板内切入（带"‹ New Workspace"面包屑，Esc 返回），不再弹出另一个独立弹窗。工作区选择器的行为全部保留——实时过滤分支/PR/Issue、`#123` 与 GitHub 链接直达、按需出现的 Base 选择器（现位于底部操作条）——切换项目后输入的关键词也不再被清空。（[#105](https://github.com/vaayne/mori/pull/105)）
- **macOS**：命令面板视觉修复：面板改为主题派生的不透明底色（此前的窗后模糊会把桌面亮度混进主题背景，呈现浑浊的灰色），右侧标签不再在面板边缘被裁切，选中高亮改为更克制的强调色圆角条。面板失去焦点时自动关闭（与 Spotlight 一致），不再出现悬浮着按 Esc 也无响应的状态。（[#105](https://github.com/vaayne/mori/pull/105)）

**完整更新日志**：[v0.6.2...v0.6.3](https://github.com/vaayne/mori/compare/v0.6.2...v0.6.3)

## [0.6.2] - 2026-07-24

### 🎨 界面优化

- **macOS**：窗口 chrome 全面重建。标题栏工具栏（以及 macOS 26 上的玻璃胶囊按钮）已移除，改为每栏各自的 38pt 细头部带——终端上方是侧栏开关、标签页和伴侣面板开关，伴侣面板上方是 **Files/Git 标签切换条**，红绿灯位于侧栏上方。头部空白区域可拖动窗口，双击遵循系统设置中的标题栏动作。终端标签最宽 220pt、过长标题截断；未选中标签保持安静（状态点 + 标题），悬停时高亮并显示关闭按钮。点击 Files/Git 标签就地切换工具；⌘E/⌘G 保持原有的开/关切换行为。（[#104](https://github.com/vaayne/mori/pull/104)）
- **macOS**：工具栏按钮退役后，其功能在别处全部可达：菜单项和快捷键不变，**命令面板获得正式菜单项**（窗口 ▸ 命令面板…，⇧⌘P），侧栏底部新增**打开项目、Agent 面板、设置**，命令面板新增切换侧栏、打开文件面板、打开 Git 面板、向右分屏、向下分屏。（[#104](https://github.com/vaayne/mori/pull/104)）
- **macOS**：侧栏状态色（agent 状态、git 指示、PR 徽章、选中强调色）不再使用固定系统色，改为从 Ghostty 主题的 ANSI 调色板派生——终端穿什么主题，Mori 的界面就配什么色，选中强调色与 tmux 活动面板边框同为主题蓝。会沉入主题背景的颜色自动向前景色方向提亮以保持可读；没有调色板的主题维持原有系统色。（[#103](https://github.com/vaayne/mori/pull/103)）
- **macOS**：终端默认带有舒适的内边距（水平 16px、垂直 12px），文字不再紧贴窗口边缘。在自己的 Ghostty 配置中设置 `window-padding-x` / `window-padding-y` 即可覆盖。（[#102](https://github.com/vaayne/mori/pull/102)）
- **macOS**：更安静的侧栏。PR 徽章默认为灰色，只在需要你处理时着色（已关闭或被要求修改保留红色编号；检查失败/进行中保留颜色，检查通过转为灰色）。选中行的高亮更明显，工作区行间距也略微放松。（[#102](https://github.com/vaayne/mori/pull/102)）

**完整更新日志**：[v0.6.1...v0.6.2](https://github.com/vaayne/mori/compare/v0.6.1...v0.6.2)

## [0.6.1] - 2026-07-23

### 🎨 界面优化（新建工作区）

- **macOS**：重新设计工作区创建面板：单个搜索框 + 一个统一列表。输入即实时过滤本地分支、开放 PR 和开放 Issue（按编号、标题或分支名），新名字会出现"新建分支"行，输入 `#123` 或粘贴 GitHub 链接直接定位到对应 PR/Issue。**Base** 选择器只在有意义时出现——新建分支或从 Issue 出发时——检出已有分支或 PR head 本就没有 base 可选。独立的"检出已有分支"标签页已移除。

### 🐛 问题修复

- **macOS**：导入已有工作区不再为每一行创建 tmux 会话（及其登录 shell）——会话改为在工作区首次被选中时惰性创建。轮询中的会话死亡恢复同样只针对当前选中的工作区，不再为每一行重建会话。
- **macOS**：git 状态轮询现在只覆盖选中的工作区和 tmux 会话存活的工作区，并分小批并发执行——导入大量工作区后不再每 5 秒产生数十个 git 进程。未轮询的行保留上次已知状态，选中后刷新。
- **macOS**：修复子进程死锁：`git`、`tmux` 或 `gh` 的输出超过 64KB 时（例如在繁忙仓库上带 CI 状态的 `gh pr list`）会填满管道缓冲区导致进程永久挂起——这也曾静默冻结侧栏的 PR 徽章。
- **macOS**：侧栏 PR 徽章不再以本地化数字分组格式渲染 PR 编号（"#16,838"）。
- **macOS**：以"删除文件"方式移除工作区不再在删除多 GB clone 时卡死应用。行显示"删除中…"，删除在后台执行；文件真正删完后行才消失，失败则恢复该行并报错。当 git 拒绝移除 worktree（有未提交改动、锁）时，错误弹窗现在提供**强制删除**重试。

### 🎨 界面优化

- **macOS**：从侧栏工作区行移除 diff 数字（`+N -M`），改为显示在行的悬停提示中。

**完整更新记录**：[v0.6.0...v0.6.1](https://github.com/vaayne/mori/compare/v0.6.0...v0.6.1)

## [0.6.0] - 2026-07-23

### ✨ 新功能

- **macOS**：将工作区创建面板重新设计为双标签对话框，只回答一个问题——新工作区检出哪个分支。**新建分支**输入名称即可基于所选**基于**分支 `checkout -b`，或从开放的 GitHub issue 起步（自动命名为 `issue-<编号>-<标题-slug>`）；若名称已是现有分支，面板会提示并直接检出而非阻止。**检出已有**是一个可筛选的列表，混合本地分支与开放的 Pull Request（选择 PR 会检出其头分支，点亮徽章与 CI 状态），并排除已有工作区占用的分支。固定的**创建工作区**按钮用于确认；回车 / ⌘⏎ / 点击均可，Esc 关闭。粘贴 GitHub issue/PR 链接——或输入 `#123`——会跳到对应标签并选中它。（[#100](https://github.com/vaayne/mori/pull/100)）
- **macOS**：侧栏工作区行的状态旁新增 Pull Request 徽章（`#编号` + CI 状态），悬停提示显示 PR 状态与标题。PR 信息在后台对所有本地工作区刷新——每个项目每 ~20 秒一次仓库级查询——不再只限当前选中项。（[#100](https://github.com/vaayne/mori/pull/100)）
- **macOS**：新建本地工作区现在采用项目目录的 APFS 写时复制克隆，`node_modules`、构建产物等未跟踪文件可立即使用（单次 `clonefile` 系统调用，数 GB 仓库也只需数秒）。新工作区会立即出现在侧栏并显示「创建中…」状态。在非 APFS / 跨卷目标上会回退到 `git worktree`（git 仓库）或普通拷贝（非 git）。「Worktree 位置」下新增设置项「新建工作区优先使用写时复制克隆」（默认开启）用于切换该行为。磁盘上的克隆会在启动时自动发现，删除克隆前会就未推送的本地提交发出警告。（[#99](https://github.com/vaayne/mori/pull/99)）

### 🎨 界面优化

- **macOS**：精简侧栏工作区行，让需要注意的状态凸显：状态行只在 agent 活动、合并冲突、创建中或有 PR 徽章时出现——「可以合并」和最近活动时间移入行的悬停提示（连同完整分支名）。diff 数字改为安静的暗色小字（去掉带边框的胶囊），⌘1–9 快速跳转提示只在按住 ⌘ 时显示。（[#100](https://github.com/vaayne/mori/pull/100)）
- **macOS**：侧栏的「新建工作区」和更多操作（「…」）移入项目标题行，作为悬停显现的图标放在折叠箭头旁，去掉了每个项目下方的独立行。尚无工作区的项目会常驻显示这两个图标。
- **macOS**：重新设计命令面板视觉呈现，加入跟随 Ghostty 主题的模糊容器、更轻的搜索区、更紧凑的列表行、更清晰的类型标签和更醒目的键盘选中状态。

**完整变更**：[v0.5.7...v0.6.0](https://github.com/vaayne/mori/compare/v0.5.7...v0.6.0)

## [0.5.7] - 2026-07-06

### 🐛 问题修复

- **macOS**：修复 agent 开始运行时侧栏 agent 图标加载失败导致 app 崩溃的问题。

### 🎨 界面优化

- **MoriRemote**：Hosts 列表管理优化 — 服务器行支持左右滑动编辑 / 删除，最近连接的主机排在最前，副标题显示默认 tmux 会话。
- **MoriRemote**：移动端工作区改为 agent-first triage 首页，按项目 / 会话展示可点击的 agent 状态 chip，并加入轻量终端顶部栏、终端内 window chips、快速切换工作区 sheet，以及用于原生复制的键盘选择模式开关。

### 📦 依赖

- 更新 libghostty（`vendor/ghostty` 子模块）到上游 `b213a72c0`，带来约 590 个上游提交的稳定性与正确性修复。

**完整变更**：[v0.5.6...v0.5.7](https://github.com/vaayne/mori/compare/v0.5.6...v0.5.7)

## [0.5.6] - 2026-07-03

### 🎨 界面优化

- **macOS**：侧栏在较窄宽度下优雅降级——agent 状态汇总条和底栏自动收起文字标签，不再在左侧被裁切；同时彻底隐藏侧栏滚动条（包括系统设置为常显滚动条的情况）。

**完整变更**：[v0.5.5...v0.5.6](https://github.com/vaayne/mori/compare/v0.5.5...v0.5.6)

## [0.5.5] - 2026-07-03

### 🎨 界面优化

- **macOS**：侧栏重构为 Conductor 风格布局——全宽仓库分区（折叠 chevron + 细分隔线）、每个仓库下的「新建工作区」行、两行式工作区行：分支名 + 相对基础分支的实时 `+增 −删` 行级 diff 徽章，第二行显示状态（运行中 / 等待输入 / 可以合并 / 合并冲突 / 最近活动）和 ⌘1–9 快速跳转提示。底栏改为「添加仓库」+ 设置。
- **macOS**：⌘1–9 快速跳转现在选择工作区（worktree）而非单个 tmux 窗口，与侧栏提示一致。
- **macOS**：$HOME 工作区固定为侧栏顶部的单行「Home」入口——一键进入 $HOME 会话，方便跑不属于任何仓库的任务。它没有工作区列表和「新建工作区」行，也不参与 ⌘1–9 索引。
- **macOS**：找回侧栏底部的 agent 状态汇总条——等待 / 运行 / 出错三个状态点加计数，为零时置灰。点击某个状态会列出处于该状态的工作区，点选即可直达。
- **macOS**：侧栏重新设计为克制的项目树——扁平的 folder 项目列表，展开后是安静的「Worktrees」分组与紧凑单行 worktree 行。移除了注意力收件箱（过滤药丸、Needs You / Running、项目字母块）。
- **macOS**：收起侧栏（⌘B）时现在完全隐藏，而不是留下一条窄的项目图标 rail，内容区铺满整个窗口。
- **macOS**：worktree 行在其 agent 正在工作时，会在最前面显示该 agent 自己的图标（Claude Code、Codex 或 Pi）——染成侧栏配色并呼吸闪动表示正在运行；无法识别的 agent 回退到通用 AI 图标。

**完整变更**：[v0.5.4...v0.5.5](https://github.com/vaayne/mori/compare/v0.5.4...v0.5.5)

## [0.5.4] - 2026-06-26

### 🎨 界面优化

- **macOS**：侧栏每个 project header 新增可见的 `+` 操作，不用打开溢出菜单也能创建新 worktree。
- **macOS**：精简侧栏 chrome，移除重复的 Projects 添加按钮和不可用的搜索图标。
- **macOS**：将命令面板改成跟随 Ghostty 主题的 HUD，替代默认白色 AppKit 面板。
- **macOS**：统一 `⌘P` 和 `⇧⌘P`，两者都打开同一个命令面板，不再分成 project-only 和 all-actions 两个面板。
- **macOS**：收紧命令面板间距，优化搜索框样式和选中行视觉。

**完整变更**：[v0.5.3...v0.5.4](https://github.com/vaayne/mori/compare/v0.5.3...v0.5.4)

## [0.5.3] - 2026-06-26

### 🐛 问题修复

- **macOS**：修复 v0.5.2 回归：通过 libghostty color-scheme mutation 应用浅色 / 深色双主题时，可能干扰新 terminal surface 启动，导致 zsh 启动文件无法稳定加载。

**完整变更**：[v0.5.2...v0.5.3](https://github.com/vaayne/mori/compare/v0.5.2...v0.5.3)

## [0.5.2] - 2026-06-26

### ✨ 新功能

- **macOS**：Mori 现在支持 Ghostty 的浅色 / 深色双主题。在 Ghostty 配置里写 `theme = light:…,dark:…`（或在 设置 → 主题 打开 **跟随系统外观** 并分别选好浅色、深色主题），切换 macOS 外观时，终端与 Mori 自身的 chrome——侧栏、窗口、面板、tmux——都会实时跟随切换。

### 🎨 界面优化

- **macOS**：调整侧栏层级：project header 保持弱化，选中的 worktree 更像两行的圆角 workspace card。Git/PR 元信息放在第二行，PR 徽标可完整显示 `#编号`，不再挤占主行。

**完整变更**：[v0.5.1...v0.5.2](https://github.com/vaayne/mori/compare/v0.5.1...v0.5.2)

## [0.5.1] - 2026-06-25

### 🐛 问题修复

- **macOS**：窗口变窄时标题栏不再整体塌缩成 `»` 溢出菜单。终端标签页改为按需伸缩——撑满两组工具栏图标之间的空间（消除尾部图标前的空白），窗口变窄或标签变多时等比缩窄到一个最小值——这样工具栏按钮始终可见，不会被挤进溢出菜单。

### 🎨 界面优化

- **macOS**：精简侧栏 filter 条——`waiting`/`running` 两个 pill 现在只显示状态点 + 数字（颜色已表明是哪个，下方分区标题也重复了文字），并且侧栏窄时 pill 文字不再竖向逐字换行。

## [0.5.0] - 2026-06-24

### 🎨 界面优化

- **macOS**：把终端标签页移进窗口标题栏（Chrome 风格），不再单独占用终端上方的一条。标签页现在填进标题栏里工具栏图标旁那块原本空着的区域，为终端腾回一整行的纵向高度。
- **macOS**：重做侧栏 worktree 行，让它像原生列表而非密集的终端节点。左侧小圆点改为承载身份与 agent 状态的 glyph——主 worktree 用分支图标、linked worktree 用节点图，按状态着色，agent 等待输入时脉冲闪动。分支名从等宽改为比例 13pt，选中行从淡渐变改为实心强调色 + 白字，「当前位置」一眼可辨。
- **macOS**：侧栏默认收为两级。tmux 窗口（第三级）现在收进 worktree 行尾的 `N ›` chip，点击才展开——单窗口的 worktree 不显示 chip，因为选中该 worktree 本就直达其窗口。项目头降级为安静的分组标签（更小的字母块、灰化名称、去掉抢眼的选中高亮），仅当其内有事需要你处理时才显示状态圆点。被收起的窗口处于等待/报错时，chip 上会出现一个小圆点，而非强行撑开该层级。
- **macOS**：收起态侧栏（rail）中，有 agent 等待你输入的项目，其外环现在会呼吸闪动（与展开态的 glyph 一致），让 dock 主动把视线引向需要处理的项目。
- **macOS**：侧栏背景相对终端区下沉一档（暗色主题压暗约 22%、亮色压暗约 6%），让 chrome 拥有独立平面，不再在共用 Ghostty 主题色时与终端糊在一起。tint 基于同步的主题色推导，「跟随 Ghostty 主题」的约定保持不变。
- **macOS**：侧栏精修——顶部 filter 条改成文字形式（`1 waiting`、`0 running`）+ 状态点 + 搜索图标，零计数状态自动隐藏，让条带在无事时保持安静。项目头从此前的灰色小标签调回真正的"组头"权重（20pt 字母块 + 14pt 加粗名称），分组感更明确，同时仍把"实心选中底"留给 worktree 行作为主角。tmux 窗口行改用与 worktree 行同一套 glyph 语言——按 agent 状态着色的小 SF Symbol（等待时脉冲），不再是不透明小圆点——让两层视觉上属于一家。
- **iOS（MoriRemote）**：更换 app 图标为 Mori 品牌图标（深绿底木桩盆栽 + 嫩芽 + `>_` 提示符），与 macOS 端统一。此前那张 AI 生成的树桩插画还把「Mori」文字烧进图标，缩到桌面尺寸就糊成一团；新图标满幅不透明，由 iOS 自行加圆角。

### ✨ 新功能

- **macOS**：在「设置 → 通用」中新增可自定义的 worktree 位置。新建的本地 worktree 会创建在该基础目录下(默认 `~/.mori`);已有的 worktree 保持原位不动。远程 SSH worktree 仍使用仓库的父目录。
- **macOS**:Mori 现在会导入仓库已有的 git worktree。添加项目时会自动带出磁盘上的全部 worktree(不再只有根目录),项目右键菜单新增「导入已有 Worktree」可随时重新扫描。已跟踪的 worktree 会跳过,重复执行只会拾取新增的。
- **macOS**：选中的 worktree 的侧栏行现在带一个紧凑的 GitHub PR 徽标——`#编号` 按 PR 状态（open/draft/review/approved/changes/merged）着色，外加一个 CI 图标（✓/✕/⧗），完整状态见 tooltip。徽标只用于展示；右键该 worktree 可在 **GitHub** 或 **DiffsHub** 打开 PR。本地 worktree 通过 `gh` 实时获取；没有 PR 或未装 `gh` 时不显示。徽标内嵌在行内，侧栏保持两级。
- **iOS（MoriRemote）**：键盘功能栏按角色和频率重排——低频 app 操作(切主机、自定义键、detach)折进最左的「•••」溢出菜单;高频上下文操作(会话切换器、tmux)常驻;其余为打字键,收键盘键钉在末尾。移除了原先紧贴 `ctrl`/`esc`、容易误触的返回键与齿轮键。
- **iOS（MoriRemote）**：侧栏改为与桌面端一致的层级——项目下分组各自的 tmux 会话（分支），每个窗口列出其窗格（带 agent 状态徽标），可在一处切换项目、标签页与窗格。

### 🐛 问题修复

- **iOS（MoriRemote）**：侧栏现在能正常列出 tmux 会话。此前查询用制表符作字段分隔符，而 tmux 会在 `-F` 输出里把它清洗成 `_`，导致每行字段全粘在一起、解析出 0 个会话（"No tmux sessions"）。改用能被 tmux 原样输出的可打印 ASCII 分隔符，并把所有 tmux 命令统一走带 `PATH` 前缀的封装，让 exec 通道上裸 `tmux` 也能解析（移除了脆弱的登录 shell 路径探测）。
- **iOS（MoriRemote）**：tmux 会话/窗口切换现在可靠生效。shell 通道会显式 attach 到服务器默认会话，并通过 `switch-client -c <tty>` 精确定位本客户端，不再从游离的 exec 通道发 `switch-client` 而误伤错误（或不存在）的客户端。
- **iOS（MoriRemote）**：tmux 快捷操作（新标签页、上/下一标签页、分屏、窗格切换、缩放、关闭窗格、detach）现在真正生效。此前它们被当作文本敲进 shell 通道，只有在裸提示符下才能到达 tmux——但窗格里通常跑着 agent，把这些按键吞掉了。现改为走 exec 通道、定位到本客户端当前会话，不论前台跑什么程序都能生效。
- **iOS（MoriRemote）**：服务器行新增可见的「⋯」菜单（编辑/删除）——此前编辑只能靠隐藏的长按触发。
- **iOS（MoriRemote）**：iPhone 键盘功能栏新增侧栏按钮,无需知道"左缘右滑"也能打开项目/标签页/窗格切换列表(也不再占用顶部一行终端空间)。

**完整变更**：[v0.4.8...v0.5.0](https://github.com/vaayne/mori/compare/v0.4.8...v0.5.0)

## [0.4.8] - 2026-06-12

### 🎨 界面优化

- 将 Mori 侧边栏重设计为注意力收件箱：新增 Needs You 与 Running agent 区块、筛选胶囊、统一状态圆点、空闲项目收纳，以及单 tile 折叠 rail。

**完整变更记录**: [v0.4.7...v0.4.8](https://github.com/vaayne/mori/compare/v0.4.7...v0.4.8)

## [0.4.7] - 2026-06-07

### ✨ 新功能

- 折叠侧边栏中展示 worktree 圆点：按项目分组平铺所有 worktree，每个圆点显示首字母和 agent 状态色环，替代之前仅显示项目图标的视图。

### 🐛 问题修复

- 恢复 v0.4.6 布局精简时误删的 agent 状态汇总条和 Agents 区块。

**完整变更记录**: [v0.4.6...v0.4.7](https://github.com/vaayne/mori/compare/v0.4.6...v0.4.7)

## [0.4.6] - 2026-06-06

### 🎨 界面优化

- 优化侧边栏和终端标签页布局：更紧凑的侧边栏密度、更清晰的标签页分隔 ([#89](https://github.com/vaayne/mori/pull/89))

### 📝 文档更新

- 重构 README：添加亮/暗/lazygit/yazi/设置截图，将 Features 移至 Mental Model 上方，折叠 Build 区块，CLI 示例精简为四个关键命令。

**完整变更记录**: [v0.4.5...v0.4.6](https://github.com/vaayne/mori/compare/v0.4.5...v0.4.6)

## [0.4.5] - 2026-04-29

### 🎨 界面优化

- 将侧边栏的 `Now` 区块重命名为 `Agents`，移除底部操作栏，把打开项目 / 搜索 / Agent Dashboard 控件移到侧边栏按钮旁边，并让设置固定在主窗口工具栏最右侧。

### 🐛 问题修复

- 修复侧边栏 `Agents` 区块会把同一个 tmux window 里的多个 agent pane 合并成一条的问题；现在每个已接入 hook 的 agent pane 都会单独显示为一行。
- 修复从侧边栏 `Agents` 区块点击 agent 行时只能切到 window、不能聚焦到对应 tmux pane 的问题；现在会直接聚焦到准确的 pane。
- 保持侧边栏 `Agents` 区块中的 tmux pane 原始顺序，不再按状态或最近活动自动重排 agent pane。
- 补上缺失的 tmux `select-pane` 后端调用，修复侧边栏 agent 行点击后表面切换了但实际没有聚焦到对应 pane、仍停留在 window 级别的问题。
- 重新设计侧边栏 `Projects` 区块的折叠控件：用带项目数量的显式显示 / 隐藏按钮替换原先含义不清的独立 chevron，让折叠状态更容易理解。

**完整变更记录**: [v0.4.4...v0.4.5](https://github.com/vaayne/mori/compare/v0.4.4...v0.4.5)

## [0.4.4] - 2026-04-29

### 🐛 问题修复

- 移除重复的 tmux 身份别名；`MORI_WINDOW` 和 `MORI_PANE` 现在是唯一的窗口 / 面板 ID 环境变量。

**完整变更记录**: [v0.4.3...v0.4.4](https://github.com/vaayne/mori/compare/v0.4.3...v0.4.4)

## [0.4.3] - 2026-04-29

### ✨ 新功能

- 在侧边栏 Projects 标题区新增隐藏 / 显示完整项目列表的按钮，方便只关注 Now 区域信息。
- 在 Mori 创建的 pane 中导出 tmux 身份环境变量（`MORI_SESSION`、`MORI_WINDOW`、`MORI_PANE` 及别名），让 `mori` CLI 可以直接定位当前 session/window/pane。

**完整变更记录**: [v0.4.2...v0.4.3](https://github.com/vaayne/mori/compare/v0.4.2...v0.4.3)

## [0.4.2] - 2026-04-23

### 🎨 界面优化

- 更新 Mori 应用图标为更贴近原生 macOS 的深色新标记：石墨质感的终端容器、刻入式提示符图形与明亮幼苗，替换此前偏树桩风格的 Dock 图标
- 重构侧边栏层级：为项目加入清晰的分组区块、弱化全局活动区的视觉权重，并强化当前工作树的焦点状态，让项目、工作树与嵌套窗口能更快区分 ([#87](https://github.com/vaayne/mori/pull/87))

### 🐛 问题修复

- 修复命令面板 / 项目切换器在输入时读取不到浮动面板内的实时搜索文本；同时将 `⌘P` / `⌘⇧P` 统一走同一套带模式的展示逻辑，让两个快捷键在切换与关闭时行为保持一致，不再维护两条分叉代码路径 ([#86](https://github.com/vaayne/mori/pull/86))

### ♻️ 重构

- 将 `mori-agent-bridge` skill 重构为模块化引用结构，便于维护并明确代理间消息协议的契约边界

**完整变更记录**: [v0.4.1...v0.4.2](https://github.com/vaayne/mori/compare/v0.4.1...v0.4.2)

## [0.4.1] - 2026-04-19

### ✨ 新功能

- 在设置 → Tools 中新增可切换的 Mori tmux 默认预设，让 Mori 管理的会话默认开启鼠标支持并隐藏 tmux 状态栏，同时也允许用户一键回退到自己 `tmux.conf` 中的鼠标与状态栏行为 ([#78](https://github.com/vaayne/mori/pull/78))

### 🐛 问题修复

- 终端字体选择器现在会包含 JetBrains Maple Mono 这类系统字体：当 AppKit 没有将其标记为等宽字体时，改为回退到统一字形宽度检测来识别 ([#78](https://github.com/vaayne/mori/pull/78))
- 安装 Agent Hook 时保留软链接的 agent 配置文件（例如指向 dotfiles 仓库的 `~/.claude/settings.json`）：原子写入现在会先解析软链接目标，避免链接被替换为普通文件 ([#81](https://github.com/vaayne/mori/pull/81))
- Lazygit / Yazi 等嵌入工具进程退出后，右侧 Git / Files 面板会立即自动关闭，不再残留一个提示 "press any key to close" 且只能通过重启 Mori 才能关闭的空白面板 ([#82](https://github.com/vaayne/mori/pull/82))
- 将 agent hook 的 tmux 更新明确绑定到触发事件的 `TMUX_PANE`，修复同一会话里一个 Claude / Codex / Pi pane 把兄弟 pane 错误标成 Running 或 Waiting 的问题 ([#83](https://github.com/vaayne/mori/issues/83))
- 每次启动时自动用 Mori bundle 内的最新资源刷新已启用的 agent hook 文件，让 `~/.config/mori/` 始终跟随当前运行版本，并在升级后自动修复陈旧脚本

**完整变更记录**: [v0.4.0...v0.4.1](https://github.com/vaayne/mori/compare/v0.4.0...v0.4.1)

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

[Unreleased]: https://github.com/vaayne/mori/compare/v0.4.2...HEAD
[0.4.2]: https://github.com/vaayne/mori/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/vaayne/mori/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/vaayne/mori/compare/v0.3.8...v0.4.0
[0.3.8]: https://github.com/vaayne/mori/compare/v0.3.7...v0.3.8
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
