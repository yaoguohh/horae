# Horae 菜单栏弹窗重设计：调研与规划

- 状态: 单栏表格已做成原生 SwiftUI（`app/Sources/Horae/`），文案按用户评审改过一轮；原型与原生实现保持一致
- 日期: 2026-11-13
- 原型入口: [方案比较](index.html)
- 范围: 调研、规划、HTML 原型，以及按第 9 节完成的原生实现；不改 Go 引擎与 JSON 契约
- 依据: 现有 SwiftUI 代码只当作功能与数据的依据，不当作视觉约束；历史 mockups、旧截图、旧标志没有参考

## 1. 要解决的问题

用户打开弹窗想在几秒内知道三件事：现在在更新什么、有没有失败、要不要自己处理。偶尔才会手动更新、暂停调度、看日志、管理来源。

读完代码后，问题归结为四点：

1. **四类事实挤在一处。** 来源是否启用、自动调度是否暂停、当前是否在执行、最近一次结果，是四个独立的事实。它们一旦共用同一个标签位或同一种颜色，就会互相覆盖，位置也对不齐。
2. **界面不能比数据更确定。** 引擎没有包数量和百分比；“下次到期”只是到期时刻；批量运行时界面只知道“第几项，共几项”，不知道接下来是谁。
3. **常驻控件过多。** 现在每一行都有更新按钮和启停开关，这两个操作都很少用，却占着每行最显眼的位置，也是列对不齐的直接原因。
4. **标志和界面各说各的。** 标志、菜单栏图标、行内状态图形、控件应当出自同一套几何，而不是各画一套。

## 2. 真实能力

来自 `app/Sources/Horae/Contract.swift`、`Engine.swift`、`Store.swift` 和引擎的 `internal/report`、`internal/control`、`internal/orchestrator`、`internal/state`。

### 2.1 界面能拿到的数据

| 数据 | 字段 | 说明 |
|---|---|---|
| 全局暂停 | `paused`、`paused_until` | `until` 为空表示暂停到手动恢复 |
| 来源 | `id`、`label`、`enabled` | `enabled` 已合并 app 侧的覆盖 |
| 最近结果 | `status`（success / failure / timeout / never）、`last_exit_code`、`last_duration` | |
| 上次成功 | `last_success_at` | 同一轮里的来源共用一个时间戳，引擎在一轮开始时只取一次 now |
| 下次到期 | `next_due_at`、`due` | 成功态 = 上次成功 + 周期；失败或超时 = 上次尝试 + 周期 |
| 当前执行 | `running`、`step`、`index`、`total`、`started_at`、`last_lines` | `last_lines` 是输出的最近若干行，首行是命令本身 |
| 最近一次运行 | `finished_at`、各项计数、每步的 `output_tail` | 单独更新一个来源也会刷新它 |
| 运行日志 | 时间、来源 id、状态、时长、`stderr_tail` | 读最近 4 个日志文件，最多 250 条，保留 14 天 |
| 排队 | app 本地的 `queued` 集合 | 只记录用户点过“更新”的单个来源 |

### 2.2 现有操作

全部更新；更新单个来源；启用或停用单个来源；暂停自动更新（1 小时、到今天结束、直到手动恢复）与恢复；展开实时输出；看日志与失败输出；打开日志文件夹；添加预设来源、删除来源、改周期、打开 `recipes.toml`；通知策略（总是、有变更时、仅失败时、从不）；登录时打开；检查软件更新；退出；按 Esc 返回或关闭。

### 2.3 必须照实表达的限制

- 来源 `enabled=false` 时，自动和手动更新都会跳过。
- 全局暂停只拦自动调度，手动更新照常。
- 启停和暂停都不会取消已经在执行的命令；引擎也没有取消命令的能力。
- 没有可靠的包数量和百分比。契约里的 `changes` 字段目前恒为空。
- 到期后要等下一次每小时检查才运行；电脑睡眠时顺延。
- **失败按周期退避。** 每周更新一次的来源失败后，要过一周才会自动重试。这直接关系到“要不要自己处理”，但现在的界面没有说。
- “全部更新”和自动运行时，界面只知道 `index / total`，不知道后面排的是哪些来源。只有用户手动点过的来源才确知在排队。

## 3. 调研

调研分三路，分别读 Apple 的规范、同类产品的官方文档与截图、设计系统与调度器文档。下面只写实际读到原文的内容；没读到的列在 3.6。

### 3.1 菜单栏项与弹窗

- HIG《The menu bar》：“Display a menu — not a popover — when people click your menu bar extra. Unless the app functionality you want to expose is too complex for a menu, avoid presenting it in a popover.” 图标用黑色和透明定义形状，系统自行着色。<https://developer.apple.com/design/human-interface-guidelines/the-menu-bar>
- SwiftUI `MenuBarExtra` 文档：“For more complex or data rich menu bar extras, you can use the window style.” <https://developer.apple.com/documentation/swiftui/menubarextra>
- HIG《Popovers》：只放“a small amount of information or functionality”；“Avoid making a popover too big”；不要弹窗套弹窗。<https://developer.apple.com/design/human-interface-guidelines/popovers>
- HIG《Typography》：macOS 正文 13/16，Callout 12/15，Subheadline 11/14，最小 10。<https://developer.apple.com/design/human-interface-guidelines/typography>
- HIG《Toggles》：macOS 上一般不要用开关替代勾选框；分组表单的行内可以用 mini 开关；状态差异不能只靠颜色。<https://developer.apple.com/design/human-interface-guidelines/toggles>
- HIG《Color》《Accessibility》：不能只靠颜色传达信息；17pt 及以下的文字对比度至少 4.5:1。<https://developer.apple.com/design/human-interface-guidelines/color>

对 Horae 的含义：实时输出和逐行操作超出了菜单的能力，用窗口样式有依据；但规范的方向很明确，要尽量像菜单、尽量小。这支持单栏、像菜单的做法。字号只用 13、12、11 三档。

### 3.2 同类产品

- **Time Machine**：菜单顶部是一行不可点的状态，完成后写“Latest Backup to … / Today, 9:41 AM”；其下的动作随状态切换，空闲是“Back Up Now”，进行中是“Skip This Backup”；不展示下次时间，正文只说“wait for the next automatic backup”。<https://support.apple.com/en-us/104984>
- **Carbon Copy Cloner**：菜单栏图标有四态，“No tasks are running / One or more tasks are running / CCC requires your attention / CCC tasks are disabled”；每行用图标表示最近结果，名称下方是下次运行时间；出错时不置顶，而是在 Activity 页签名前加警示图标；全局“Suspend all tasks”带一小时到一周的档位和无限期，与单任务停用互不影响。<https://support.bombich.com/hc/articles/20686467217687>
- **Dropbox**：暂停档位“30 minutes / 1 hour / Until tomorrow / Indefinitely”，暂停后持续显示“File sync and backups paused until 3:22 PM”；菜单栏图标区分已同步、同步中、已暂停、出错。<https://help.dropbox.com/sync/pause-resume>、<https://help.dropbox.com/sync/sync-icons>
- **Maestral**（源码）：问题用带计数的入口“Show Sync Issues (n)...”，没有问题时是“No Sync Issues”。<https://raw.githubusercontent.com/samschott/maestral-cocoa/main/src/maestral_cocoa/app.py>
- **topgrade**（源码）：结束时每步一行“名称: 状态”，按执行顺序，不把失败置顶；失败时提示“Retry?”。<https://raw.githubusercontent.com/topgrade-rs/topgrade/main/src/terminal.rs>
- **Latest**：列表分组，“Available Updates (5)”在上、“Installed Apps (63)”在下。<https://github.com/mangerlahn/Latest>
- **OrbStack、syncthing-macos、Backblaze**：顶部状态、分组标题、动作在下的菜单式结构；设置与日志另开窗口。<https://docs.orbstack.dev/menu-bar>、<https://github.com/syncthing/syncthing-macos>

至少两个产品出现的做法：

1. 顶部一行状态文字，动作在其下（Time Machine、Backblaze、syncthing-macos、Maestral）。
2. 菜单栏图标区分空闲、进行中、暂停或停用、需要处理（CCC、Dropbox）。
3. 暂停是全局的，带限时档位和无限期，界面持续显示恢复时刻（Dropbox、CCC、Arq）。
4. 完成时间写成“Today, 时刻”的绝对时间（Time Machine、Backblaze）。
5. 问题怎么露出有两派：用计数或单独入口而不改变列表顺序（CCC、Maestral、topgrade）；按严重度分组或置顶（Latest，以及 3.3 里的 GitLab、PatternFly）。

第 5 条两边都有成熟先例。现在的三个版本都让未成功的来源留在原位，由头部一句话提醒。

### 3.3 状态怎么表达

- Carbon《Status indicator pattern》：图标型状态要有图标、形状、有意义的颜色和文字标签；指示种类超过五六种会压垮用户；不需要用户行动时用纯文字；同一界面避免“同一形状配不同颜色”。<https://carbondesignsystem.com/patterns/status-indicator-pattern/>
- Atlassian lozenge：“Don't use color alone to signify an important attribute”；填充图标滥用会削弱关键状态。<https://atlassian.design/components/lozenge/usage>
- PatternFly：多个严重度图标按从重到轻排列并附计数。<https://www.patternfly.org/patterns/status-and-severity/>
- GitHub checks：`queued`、`in_progress` 是状态，`failure`、`timed_out`、`skipped` 是结论，两组分开。<https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/collaborating-on-repositories-with-code-quality-features/about-status-checks>
- NN/g 错误信息准则：靠近出错处显示；不能只靠颜色或动画；说清问题并给出下一步；错误码只作诊断用。<https://www.nngroup.com/articles/error-message-guidelines/>

对 Horae 的含义：状态图形控制在六种以内，每种形状不同；成功不用彩色；“当前活动”和“最近结果”像 GitHub 那样分成两组事实；失败处写明发生了什么和能做什么，退出码放在次要位置。

### 3.4 调度时间与暂停

- systemd `list-timers`：NEXT / LEFT / LAST / PASSED 四列，绝对与相对并列；timer 的措辞是“scheduled to elapse within a time window”。<https://www.freedesktop.org/software/systemd/man/latest/systemctl.html>
- launchd：`StartInterval` 在睡眠期间的触发“will be missed”。<https://keith.github.io/xcode-man-pages/launchd.plist.5.html>
- GitHub schedule：“can be delayed during periods of high loads”。<https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows>
- Kubernetes CronJob 的 suspend：暂停期间“they remain scheduled, but the CronJob controller does not start the Jobs”，不影响已启动的任务。<https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/>
- Windows Update：暂停“doesn't permanently turn off automatic updates”，到期自动恢复。<https://support.microsoft.com/en-us/windows/deployment/updates-lifecycle/pause-updates-in-windows>
- Buildkite：“You can also run a disabled schedule once without enabling it.” <https://buildkite.com/docs/pipelines/configure/workflows/scheduled-builds>
- Atlassian、GitLab Pajamas、Cloudscape：相对时间适合“多久以前”，需要具体时刻（含将来）时用绝对时间，并能查到绝对时间。<https://atlassian.design/foundations/content/date-time/>、<https://design.gitlab.com/content/date-and-time>、<https://cloudscape.design/patterns/general/timestamps/>

对 Horae 的含义：下次时间写“最早 20:04”，不写“下次 20:04”；列里用绝对时间，便于按列对齐。Buildkite 允许停用后手动跑一次，Horae 恰好相反，所以停用处必须写明“自动和手动都会跳过”，不能指望用户按别处的经验猜对。

### 3.5 没有百分比时的进度

- HIG《Progress indicators》：不可量化的任务用不确定指示；要尽量准确，否则“can … even feel deceptive”；说明文字避免“loading”这类空话。<https://developer.apple.com/design/human-interface-guidelines/progress-indicators>
- Nielsen 1993：工作量未知时，可以给“running progress feedback in terms of the absolute amount of work done”；转圈是最后的办法。<https://www.nngroup.com/articles/response-times-3-important-limits/>
- NN/g：循环动画只适合 2 到 10 秒，更长的等待需要更多信息。<https://www.nngroup.com/articles/progress-indicators/>

对 Horae 的含义：更新常常超过 10 秒，只转圈不够。用“已用时间 + 输出末行”作为已完成工作量的如实反馈，不画进度条。

### 3.6 没能核实的

- 菜单栏图标的具体尺寸：HIG 只给了菜单栏高度 24pt。
- 弹窗内部能否做多级页面：HIG 只禁止弹窗套弹窗，没有提内部导航。
- CCC、Dropbox 在暂停期间能否手动触发：文档没写。
- Docker Desktop、Tailscale 的菜单文案：页面没读到。
- 各产品面板的像素尺寸；“排队、暂停、停用”在 SF Symbols 里有没有约定符号：没有对应材料。
- 多数产品的界面截图没能读取，上面的观察以文档正文和源码为准。

## 4. 任务与信息优先级

| 优先级 | 任务 | 需要的信息 | 频率 |
|---|---|---|---|
| 1 | 确认一切正常 | 一句总述 | 每次打开 |
| 2 | 看正在更新什么 | 来源名、已用时间、输出末行、第几项 | 运行时 |
| 3 | 判断失败要不要处理 | 哪个来源、什么原因、何时自动重试 | 出错时 |
| 4 | 手动更新 | 全部或单个 | 偶尔 |
| 5 | 暂停与恢复自动更新 | 暂停到何时 | 偶尔 |
| 6 | 看日志、管理来源、改设置 | | 很少 |

由此得出：第 1 到 3 项必须在主弹窗里不点任何东西就能看到；第 4、5 项一步可达；第 6 项可以多一步。

## 5. 状态规则（各版共用）

1. **四类事实分开。** 启用、调度、当前活动、最近结果，任何一类都不借用另一类的位置或颜色。
2. **每个来源一个主状态**，优先级：已停用 > 正在更新 > 排队中 > 未成功（失败或超时）> 尚未运行 > 成功。
3. **头部一句总述**，优先级：正在更新 > 有未成功 > 已暂停 > 全部正常。有未成功时写出来源名；只有一项时直接写“某某更新失败”。
4. **暂停有一个固定的位置。** 底部工具栏左侧在暂停时变成“恢复自动更新”并写明暂停到何时；头部空着时也由头部说一遍。
5. **运行中**显示已用时间和输出末行，可展开看最近几行；显示“第几项，共几项”；不画进度条，不提供“停止”。
6. **排队**只标在用户手动点过的来源上。批量运行里尚未轮到的来源如实显示为“已到期”。
7. **“下次最早”**：未到期显示到期时刻；已到期显示“已到期”；失败或超时显示自动重试的最早时刻；暂停期间取到期时刻与暂停结束时刻中较晚的一个，无限期暂停时显示“已暂停”；已停用显示“已停用”。
8. **时间写法**：列里用绝对时间，今天只写时刻，其余写“明天 09:12”“11-16”；数字用等宽数字。
9. **停用**写明“自动和手动都会跳过”，不给更新按钮，只给“启用”。
10. **颜色**：成功不上色、不放图形；彩色只给运行中（蓝）和未成功（红）。未成功同时有图形、颜色、文字。按钮和开关不用实心蓝。
11. **“最近一次运行”**照字面使用，不写成“上次同步”。单独更新一个来源后，它就是那一次。

## 6. 页面关系

- 主弹窗：总述、来源列表、全局操作。
- 日志：按天列出每次执行；未成功的条目可展开看输出，并可重试、拷贝输出。主弹窗里未成功的来源直接跳到它那一条。
- 来源管理：已添加的来源（启用、周期、命令预览、移除）；可添加的预设；打开 `recipes.toml`。
- 设置：管理来源入口、通知策略、登录时打开、软件更新、版本、退出。

## 7. 能力分级

**现有能力**：见 2.2。

**界面新增，数据已有**（不需要改引擎）：

- 从未成功的来源直达它的失败输出。
- 显示“自动重试最早”的时刻（就是 `next_due_at`）。
- 显示“第几项，共几项”（`current.index / total` 现在没有用上）。
- 菜单栏图标增加“需要处理”和“已暂停”两态（现在只有运行时的脉动）。
- 日志显示来源名称而不是 id；只看未成功；拷贝输出。
- 暂停期间“下次最早”顺延显示。
- 浅色外观（现在强制深色）。
- 失败时刻：`status` 里没有上次尝试时间，要从日志取，或用 `next_due_at` 减去周期反推。

**需要引擎配合**（原型里都没有画）：

- 取消正在执行的命令。
- 包数量、版本变更明细、百分比。
- 批量运行时接下来是哪些来源。
- 只重试未成功的来源；按来源暂停。
- 在 `status` 里直接给出上次尝试时间和周期。

## 8. 已经定下的事与仍按默认做的事

用户在几轮评审里明确定下的：

- **选定单栏表格。** 看过多个方向和版本后，用户选了最早的台账这一路里的表格版。
- **来源的品牌小图标保留。** 最初的设计把它去掉，只当作一条待判断的假设，没等回复就拿去实施，这是错的。
- **标志不随状态变色。** 标志是品牌，整体状态已有头部一句话、各行和菜单栏图标表达。
- **失败状态不能刺眼。** 实心红圆加粗红字过重，改成小红点加常规字重的暗红字。
- **不要实心蓝。** 实心蓝按钮和蓝色标志方块在灰白的表格里太突兀。现在标志是淡蓝底配蓝色 H，按钮全是灰色，开关打开是深灰。
- **底部不要直接铺一串功能。** 改成一条工具栏，不常用的收进设置。
- **演示数据要像真实环境**，其中有 Hermes。

仍按默认做、等用户看了再说的：

1. “最早 20:04”这个说法足够清楚。
2. 单个来源的“更新”平时收起，悬停才出现。
3. 启停开关不出现在主列表的每一行，放到管理来源里。
4. 日志、设置、管理来源留在弹窗内，不另开窗口。
5. 跟随系统的浅色与深色外观。

## 9. 选定的设计

原型是 [ledger.html](ledger.html)，[入口页](index.html)把它的各个状态和次级页摆在一起。

**主弹窗**，宽 344：

- 头部：标志、一句话总述和一行补充，右边是“全部更新”。
- 表头与来源表：品牌小图标、名称、上次、下次最早。进行中的行右侧是蓝色转圈和已用时间，下面一行是输出末行，可以展开；未成功的行右侧是红点和“失败”或“超时”，下面一行是原因、时间和自动重试的最早时刻，点它进日志；排队的行右侧是虚线环和“排队中”；停用的行图标变灰。
- 悬停一行时，两列时间的位置换成“更新”（未成功时是“重试”，停用时是“启用”）和“更多”。
- 底部工具栏：左边是“暂停自动更新”，点开选一小时、到今天结束或直到手动恢复；暂停后变成“恢复自动更新”并写明暂停到何时。右边两个图标按钮是日志和设置。

**次级页**：

- 运行日志：按天列出，未成功的条目可以展开看输出、重试、拷贝输出；可以只看未成功；可以打开日志文件夹。
- 设置：第一行进管理来源；然后是通知策略、登录时打开、软件更新；底部是版本号和“退出 Horae”。
- 管理来源：从设置进。已添加的来源有开关、周期和命令预览；下面是可添加的预设；底部可以打开 `recipes.toml`。周期从常用档位里选（1、2、4、6、8、12 小时，1、2、3 天，1、2 周），组合周期只读。移除来源在行的右键菜单里，选后在行内确认一次。
- 弹出菜单（行的“更多”、暂停、周期、通知）画在弹窗内部，悬停是灰色，宽度随最长的一项。

**文案**（用户评审后定下）：

- 菜单项不带省略号，除非后面还要确认（“移除此来源…”）；行菜单里不重复“此来源”：查看日志、修改周期、停用。
- 同一个事实只说一次：日志展开后只写原因（时长已在行右侧）；版本号只在设置页脚写。
- 运行中的补充写“第 1/4 项，已用 24 秒，1 项未成功”，放得进一行。
- 拉丁字母或数字与汉字相邻时留一个空格：“Homebrew 更新失败”“npm 全局包更新失败”。
- 周期统一写“每天”“每周”“每 8 小时”。
- 界面里不说“配方”，文件名 `recipes.toml` 只出现在打开它和删除确认两处。
- “登录时打开”而不是“开机自启”（实际是登录项）；软件更新的按钮叫“检查新版本”，和更新来源区分开。
- 无限期暂停时，底栏写“已暂停”，头部补充写“不会自动恢复，手动更新不受影响”。
- 系统通知的标题与头部同一套说法（“更新完成”“npm 全局包更新超时”“2 项需要处理”），正文时长用“2 分 31 秒”的写法。

**颜色**：整体灰白。彩色只有三处——来源的品牌小图标、进行中的蓝、未成功的一个小红点和暗红色的字。标志是淡蓝底上的蓝色 H。未成功最初是实心红圆加粗红字，用户认为过重、刺眼，降成了现在这样；暗红字在浅色和深色底上的对比度都是 5.4:1。

**菜单栏图标**：单色的 H，空闲、运行、需要处理、已暂停四种形状。

尺寸（8 个来源，实测）：常态 360，执行 376，两项未成功 392；13 个来源时 442，列表区内滚动。

## 10. 走过的路

这些都做过原型，已放弃并删除，这里只留结论：

- **分诊**：按要不要处理分组，未成功的来源置顶并带输出。来源会随状态换位置，高度变化大。
- **工作台**：两栏，左边选来源、右边看详情。面积约为单栏的三倍，更像小窗口。又做过两个换皮版：一个用 Tern.app 的设计语言和 anthracite 配色，一个照 AffectUI 的 clean 风格。
- **卡片**与**图标墙**：和表格并排比较过的两个简洁版本。卡片每行两行字、最高；图标墙只有图标和名称，时间要点开才看到。
- **菜单**：每行只留一个值。和表格只是疏密不同，并排时看不出是两个版本。

教训：一是加层次、加材质没有解决“素”，反而离简洁更远；二是未经确认的假设不能直接拿去实施；三是给人选的几个版本要一眼能分开，入口页打开就该并排、有编号。

两份设计语言的材料以后可能还用得上：Tern 的样式内嵌在 `/Applications/Tern.app/Contents/Frameworks/libtern.dylib` 里，可用 `strings` 读出；AffectUI 的组件源码在 `~/Work/ai/museion-harness/.local/affectui/src/`。

## 11. 验证记录

用无头 Chrome 逐个状态渲染，并用脚本读取元素位置、模拟点击。

- **对齐**：标题、表头、名称、第二行说明、底部左侧按钮的文字，以及次级页的标题和各行文字，左缘都在 40；右缘都在距边 14。
- **基线**：名称（13）与时间（11）共用基线。
- **字号**：只有 13、12、11。
- **控件**：按钮高 22，底部工具栏的按钮高 26。
- **内容压力**：13 个来源和长名称下没有溢出；长名称用省略号截断，悬停提示里有全名。
- **交互**：13 条路径全部通过，没有脚本报错：行的更多菜单、进管理来源、返回到设置、返回主弹窗、展开实时输出、失败行进日志并展开、只看未成功、暂停菜单、底部进日志、底部进设置等。
- **浅色与深色**：各渲染查看过一遍。

没有验证的：原生 SwiftUI 下的实际渲染；真实的毛玻璃材质效果；键盘操作与 VoiceOver。弹窗用了半透明材质，没有逐色计算对比度；文字色值沿用最早那版台账，当时按不透明底算过，正文、次要文字、状态色都不低于 4.5:1。

## 12. 原生实施的状态

按第 9 节完成，代码在 `app/Sources/Horae/`：

- `MainPage.swift`、`LogPage.swift`、`SettingsPage.swift`、`SourcesPage.swift`：主弹窗与三个次级页，在同一个弹窗里换页，Esc 先关弹出菜单、再返回上一级、最后关闭弹窗。
- `Board.swift`：第 5 节的状态规则与全部措辞。
- `Theme.swift`：颜色、字号、圆角、间距、尺寸、阴影、动效都是令牌，颜色各有浅深两个值，取自 `ledger.html` 的 CSS 变量；视图里不写字面量。
- `Glyphs.swift`：H 标志、菜单栏图标四态、状态图形和控件图标出自同一套 16 格几何。
- `Controls.swift`：灰色按钮、开关、下拉、弹出菜单等共用控件。

和原型的差别，都是原生环境决定的：

- 选中文字的颜色、弹窗外沿、阴影与圆角由系统画；底色是系统材质再压一层 panel 色。
- MenuBarExtra 的窗口只随内容长高，换到更矮的页面时由代码把窗口收回内容高度，顶边不动。
- 弹出菜单没有系统菜单那样的方向键选择；移除来源的右键菜单是系统菜单。

验证：用 `XDG_STATE_HOME`、`XDG_CONFIG_HOME` 指向临时目录的夹具（`horae run` 一律拦下）让各状态出现，浅色与深色逐张和原型对照过。键盘操作与 VoiceOver 还没有验证；“排队中”要点“更新”才会出现，没有在夹具里截过。

实施中发现的两个原有问题，都在本轮范围外，需要用户定：

- 设置里的通知策略没有任何地方读取，是否发通知由 `recipes.toml` 里的 `defaults.notify` 决定。
- `last-run.json` 在每小时的空检查里也会被覆盖成 `ran=0`，所以“最近一次运行”改从运行日志取。

## 13. 文件

- [入口页](index.html)：各个状态和次级页
- [弹窗原型](ledger.html)：用地址参数 `state`、`page`、`theme`、`data` 选择要显示的内容
- `shared.js`、`shared.css`：演示数据、状态规则、标志和桌面外框
