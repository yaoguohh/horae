# horae — 统一更新编排器 · 设计文档

- 状态: 设计已审批，待落实现规划
- 语言: Go 1.26
- 平台: macOS (Apple Silicon, Tahoe)，个人单机
- 更新日期: 2026-05-29

---

## 1. 背景与动机

当前机器上有两个各自独立的自动更新组件，都在正常运行：

- **homebrew-autoupdate**（社区 `homebrew/autoupdate` tap）：launchd `com.github.domt4.homebrew-autoupdate`，每 6h + 开机即跑，执行 `brew update && brew upgrade --formula && brew upgrade --cask && brew cleanup`。
- **npm-globals-autoupdate**（自建）：launchd `com.user.npm-globals-autoupdate`，每 8h 跑 `~/.local/bin/npm-globals-update.sh`（zsh + jq 解析 `npm outdated -g --json`，逐包 `npm i -g pkg@latest`，osascript 通知）。

**真实问题不是"没跑"，而是观测割裂 + 扩展成本高**：

1. **观测割裂**：两套互不相干的日志约定。npm 脚本把日志 `>>` 写进 `npm-globals-autoupdate.log`，但其 launchd 的 `StandardOutPath`/`StandardErrorPath` 指向另两个文件（`*.stdout.log`/`*.stderr.log`，长期 0 字节），查这两个文件会误以为"从没跑过"。没有任何"谁、何时、更新了啥、跑没跑"的统一视图。
2. **扩展成本高**：每加一个更新源（pipx / cargo / rustup / gcloud …）就要另写一套 plist + 脚本 + 日志约定，碎片只增不减。
3. **通知易错过**：`display notification` 横幅一闪而过，勿扰模式直接吞掉。

`horae` 的价值主张是**收编碎片**：用一份配置统一描述所有"命令式更新源"，单个 launchd 触发器驱动，统一日志 + 统一通知 + 一个 `status` 子命令一眼看清状态。

---

## 2. 目标 / 非目标

### 目标

- 一份 TOML recipe 描述任意数量的"更新源"，每个源带自己的频率（cadence）、超时、环境。
- **单个 launchd LaunchAgent** 作为唯一触发器；工具每次 run 一次即退出，不常驻。
- 各源按自己的 cadence 自决是否该跑（anacron 模型），机器睡眠/关机错过的，开机后自动补跑。
- 跨运行的持久状态：每个源记录上次成功时间、退出码、耗时、结果。
- `horae status` 一眼看清每个源的上次结果与距下次到期时间。
- 统一结构化运行日志，路径单一、可直接 grep。
- 单静态二进制（macOS 等同零运行时依赖），装一次长期不腐。
- 收编现有 brew + npm 两个组件，卸载其旧 launchd agent。

### 非目标（YAGNI，本期明确不做）

- 多机 / 远程机器更新
- Web dashboard
- 插件系统 / 动态加载
- 真原生 macOS 通知（需 CGo + 签名 .app，破坏单二进制与免维护，不值）
- TUI 交互层（架构留门，本期不做）
- 跨平台（仅 macOS）

---

## 3. 语言决策：Go

经 5 路并行调研 + 1 路独立事实复核，候选语言对照本场景权重（分发与稳定性优先 → 子进程编排 → 配置驱动 → 通知 → 未来可加 TUI → 维护/学习）：

| 语言 | 单二进制/分发 | 长期不腐 | 子进程编排 | 学习曲线 | 契合度 |
|---|---|---|---|---|---|
| **Go** | go build 直出单文件、交叉编译一等公民 | Go 1 兼容承诺、依赖几乎全在 stdlib | stdlib `os/exec`+`context` 原生超时 | 低-中，零配置工具链 | 8 |
| Rust | cargo 直出、零运行时 | edition + 基石 crate，编译期挡 bug | std::process 够用，超时要加 crate | 高，所有权心智 | 8 |
| Python | PyInstaller 28-180MB 自解压 / uv 需装 uv | venv/依赖漂移 | subprocess.run 极顺 | 最低 | 7 |
| Node/TS | Deno/Bun --compile ~28MB+ 内嵌运行时 | Bun 高速迭代、Deno 构建非确定 | Bun.spawn/execa 完善 | 低 | 6 |
| zsh(现状) | 无法编译成二进制 | 随 OS 升级最脆、无类型、无原生超时 | 要 shell-out 到 gtimeout/jq | 零 | 2 |

**Rust 与 Go 本质平手**（两者在 macOS 都动态链接系统 libSystem，苹果不支持 fully-static，等同零运行时依赖；通知两边务实解都回到 spawn osascript，不构成区分）。选 **Go** 的决胜理由：

1. **维护成本是隐藏最高权重**：工具小、solo 维护、偶尔回来加源。Go 语法极小、`os/exec`+`context` 与熟悉的 Python `subprocess.run` 同构，几个月后仍一眼读懂；Rust borrow checker 是每次回来都付的税。
2. **平手项 Go 不输**：Go 1 兼容承诺 track record 更久；`go build`/`gofmt`/`go test` 零配置（无 venv/无 bundler/无 edition 顾虑）；`log/slog` 自带结构化日志。
3. **超时 Go 更省**：`exec.CommandContext` + `WaitDelay` 是 stdlib 一等公民，无需外部依赖。

> Rust 唯一实打实优势：serde 让 recipe 解析期即强类型校验、运行时惊喜更少，且可直抄同类先例 topgrade 源码。架构与本设计完全一致，仅换库——保留作随时可翻盘的备选。

同类先例 **topgrade**（Rust，4.1k stars，v17.5.1 @ 2026-05，活跃）提供"step + summary 表 + keep-going + 自定义命令 + --dry-run/--only/--skip"模型；其三个空白（无 per-step 频率、无 per-step 超时、无跨运行历史）正是本工具要补的。频率与补跑模型借鉴 **anacron**（period + 持久时间戳，按"距上次成功多久"判定，天然补跑）。

---

## 4. 核心概念

- **step（更新源）**：一个可执行的更新动作，由 recipe 中一个 `[[step]]` 表描述。最小单元。
- **recipe**：`recipes.toml`，一组 step + 全局默认值。
- **cadence（频率）**：该 step 期望多久跑一次，humantime 字符串（`6h`/`8h`/`1d`/`7d`）。
- **state（状态）**：`state.toml`，每个 step 一条跨运行记录。既是 cadence 判定依据，又是可观测性数据源。
- **run（一次编排）**：launchd 触发一次 `horae run`，遍历所有 step，跑到期的，写 state + 日志，发 summary。

---

## 5. 架构与数据流

```
launchd LaunchAgent (StartInterval 3600s + RunAtLoad)
        │  · 必须是 LaunchAgent(用户 GUI 会话)，通知才弹得出
        │  · 频率(1h)略密于最短 cadence(6h)，保证睡醒后及时补跑、又不真高频更新
        ▼
   horae run                      ← 跑一次即退出，不常驻
        │
        ├─ 取单实例文件锁(flock)   ← 防上一轮未完成时并发
        ├─ 读 recipes.toml → []Step (强类型)
        ├─ 读 state.toml   → map[id]State
        ├─ for each step(enabled):
        │     due? = now - state.last_success_at >= step.cadence
        │     ├─ 否 → 记 Skipped(未到期)，进 summary
        │     └─ 是 → 注入 PATH+env，spawn(超时, stdin=/dev/null, 进程组)
        │              捕获 stdout/stderr/exit/耗时
        │              成功 → 更新 last_success_at；失败/超时 → 只更新 last_attempt/last_status
        ├─ 写回 state.toml
        ├─ 追加结构化运行日志 (~/Library/Logs/horae/run-YYYYMMDD.log)
        └─ 按 notify 策略发 summary 通知(osascript)
```

核心解耦：**"多久戳一次"是 launchd 的事，"该不该跑"是工具按各 step cadence 自决的事**。两者正交。

---

## 6. 配置 schema：`recipes.toml`

默认位置 `~/.config/horae/recipes.toml`（可 `--config` 覆盖）。

```toml
[defaults]
timeout = "10m"          # 每个 step 默认超时
notify  = "on_change"    # always | never | on_change | on_failure

[[step]]
id      = "brew"
label   = "Homebrew 公式与 Cask"
cadence = "6h"
command = ["/opt/homebrew/bin/brew", "upgrade"]

[[step]]
id      = "npm-globals"
label   = "npm 全局包"
cadence = "8h"
shell   = "npx npm-check-updates -g -u && npm update -g"
# npm/node 不在 launchd PATH 时用 env 注入（如自定义 prefix ~/.npm-global）：
# env   = { PATH = "$HOME/.npm-global/bin:/opt/homebrew/bin:/usr/bin:/bin" }

[[step]]
id      = "pipx"
label   = "pipx 应用"
cadence = "1d"
command = ["pipx", "upgrade-all"]
enabled = false                   # 以后想加只改这一行
```

字段表：

| 字段 | 位置 | 类型 | 必填 | 含义 |
|---|---|---|---|---|
| `timeout` | `[defaults]` | duration 字符串 | 否(默认 `10m`) | step 未显式设 timeout 时的默认值 |
| `notify` | `[defaults]` | enum | 否(默认 `on_change`) | 通知策略，见 §11 |
| `id` | `[[step]]` | string | 是 | 唯一标识，state 与日志按它索引 |
| `label` | `[[step]]` | string | 否(默认=id) | 人类可读名，用于 summary/status/通知 |
| `cadence` | `[[step]]` | duration 字符串 | 是 | 期望频率，`6h`/`1d`/`7d` |
| `command` | `[[step]]` | string[] | 与 shell 二选一 | argv 数组，不起 shell（防注入/引号问题） |
| `shell` | `[[step]]` | string | 与 command 二选一 | shell 片段，用 `$SHELL -c` 执行（需要管道/展开时用） |
| `timeout` | `[[step]]` | duration 字符串 | 否 | 覆盖 defaults.timeout |
| `env` | `[[step]]` | table(string→string) | 否 | 追加/覆盖该 step 的环境变量 |
| `enabled` | `[[step]]` | bool | 否(默认 true) | false = 永不跑（保留配置占位） |

duration 字符串支持 `s/m/h/d/w`（`time.ParseDuration` 原生支持到 `h`，`d`/`w` 由约 15 行自定义解析器在其上扩展，保持 stdlib-only）。

---

## 7. 状态 schema：`state.toml`

默认位置 `~/.local/state/horae/state.toml`（XDG 风格；目录自动创建）。

```toml
[brew]
last_attempt_at = 2026-05-29T07:22:24+08:00
last_success_at = 2026-05-29T07:22:24+08:00
last_exit_code  = 0
last_duration   = "41s"
last_status     = "success"      # success | failure | timeout | skipped | never

[npm-globals]
last_attempt_at = 2026-05-29T05:58:01+08:00
last_success_at = 2026-05-29T05:58:01+08:00
last_exit_code  = 0
last_duration   = "4m15s"
last_status     = "success"
```

**关键设计**：`last_success_at` 同时是 cadence 判定依据（§9）和 status 展示数据。网络失败/超时**只更新** `last_attempt_at` 与 `last_status`，**不更新** `last_success_at`——所以下次到期仍会自然重试。单实例锁保证无并发写，整文件 read-modify-write 即可。

状态存储用 **TOML 单文件**（非 sqlite）：记录数极少、人类可直接读、可 grep、零额外依赖（sqlite 的 CGo 驱动会破坏单静态二进制，纯 Go 驱动对此场景过重）。

---

## 8. CLI 接口

| 命令 | 作用 |
|---|---|
| `horae run` | launchd 入口：遍历所有到期 step 并执行 |
| `horae run --only brew,npm-globals` | 只跑指定 step（忽略 cadence，立即跑） |
| `horae run --skip pipx` | 跑除指定外的到期 step |
| `horae run --force` | 跑所有 enabled step（忽略 cadence） |
| `horae run --dry-run` | 只打印"本次会跑哪些 / 跳过哪些及原因"，不执行 |
| `horae status` | 渲染每个 step 的上次结果 + 距下次到期 |
| `horae --config <path>` | 覆盖 recipe 路径（全局 flag） |

`status` 输出示意：

```
$ horae status
源             上次成功        上次结果   耗时      距下次到期
brew           今天 07:22      ok         41s       5h12m
npm-globals    今天 05:58      ok         4m15s     6h45m
pipx           —              未启用      —         —
```

（"上次结果"只展示 state 里实有的 `last_status`/`last_exit_code`/`last_duration`——通用编排器不解析各更新器输出，不臆造"更新了几个包"这类它无从得知的信息。）

CLI 用 stdlib `flag` + 手写子命令分发（仅 run/status 两个子命令，引入 cobra 是过度工程；若日后要 shell completion 再换，成本极低）。

行为约定：

- `--only`/`--skip` 传入 recipe 中不存在的 step id → 报错并 `exit 2`（防拼写错被静默吞成空跑 + `exit 0`）。
- `enabled=false` 的 step 即便被 `--only` 点名也**不执行**（禁用优先于点名，`enabled=false` 表示永不跑）；提示会说明"--only 命中但已禁用"，避免"--only 了却没反应"的困惑。
- 撞单实例锁（上一轮还在跑）→ `exit 0` + 提示，不计为失败 run。

---

## 9. 调度：单 launchd 触发器 + anacron cadence + 补跑

### launchd（唯一触发器）

`~/Library/LaunchAgents/com.user.horae.plist`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>            <string>com.user.horae</string>
  <key>ProgramArguments</key>
  <array>
    <string>__HOME__/.local/bin/horae</string>
    <string>run</string>
  </array>
  <key>StartInterval</key>    <integer>3600</integer>
  <key>RunAtLoad</key>        <true/>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>           <string>/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>StandardOutPath</key>  <string>__HOME__/Library/Logs/horae/launchd.out.log</string>
  <key>StandardErrorPath</key><string>__HOME__/Library/Logs/horae/launchd.err.log</string>
  <key>ProcessType</key>      <string>Background</string>
  <key>LowPriorityIO</key>    <true/>
</dict>
</plist>
```

### cadence 判定与补跑

- launchd 每 1h 唤起一次 `horae run`；工具对每个 step 比较 `now - last_success_at >= cadence` 才跑。`cadence=6h` 的源即使每小时被戳也只 6h 跑一次。
- **补跑不依赖 launchd**：判定基于"距上次成功多久"而非"某绝对时刻是否到过"，所以机器睡眠/关机错过后，开机下次唤起时所有 overdue step 自动补跑。（已知 launchd 局限：`StartInterval` 睡眠错过直接丢、关机两种 key 都不补——正因如此把补跑放进工具的 cadence 判定。）
- launchd 频率（1h）设得略密于最短 cadence（6h），保证睡醒后及时补跑，又不会真的高频跑实际更新。

---

## 10. 健壮性硬规则

先例反复踩的坑，全部预先堵上：

1. **PATH 注入与裸命令解析**：launchd 下环境近乎空（`brew: command not found` 经典坑）。plist `EnvironmentVariables` 设 PATH；工具用 `DefaultPATH()`（前置 `/opt/homebrew/bin`）作为 basePATH 注入子进程 env。**关键**：`exec.LookPath` 只读进程 ambient PATH、不读 `cmd.Env`，所以 runner 对裸命令（不含 `/`）**显式在 basePATH 各目录里查找二进制**再用绝对路径执行，使注入的 PATH 真正生效。二进制在 `~/.local/bin`/`~/.cargo/bin` 等**非标准目录**的源，recipe 用**绝对路径**（如 npm 步骤），不要依赖裸命令解析。
2. **单实例锁**：state 目录下 `horae.lock`，`syscall.Flock(LOCK_EX|LOCK_NB)`；拿不到锁说明上一轮还在跑，本次以 `exit 0` 退出（不计为失败 run），不阻塞、不并发写 state。
3. **超时 + 防交互挂起**：每 step `exec.CommandContext(ctx,…)` + `cmd.WaitDelay`；`cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}` 建进程组，超时 `syscall.Kill(-pgid, SIGKILL)` 整组杀（brew/npm 常 fork 孙进程）；`cmd.Stdin = nil`（exec 默认接 /dev/null）防更新器等 y/n 无限挂起；summary 标 `timeout`。
4. **网络失败不算成功**：拉取失败计入 `last_status` 但不更新 `last_success_at`，下次到期自然重试。
5. **keep-going**：单个 step 失败不中断整体，全部跑完后聚合 summary。

---

## 11. 通知策略

`notify` 四档：

| 值 | 行为 |
|---|---|
| `always` | 每次 run 结束都通知（含"无更新"） |
| `never` | 从不通知，只写日志 |
| `on_change` | 仅当本次确有 step 被执行（到期触发），或有失败/超时时通知；全部未到期被跳过则静默（**默认**，降噪） |
| `on_failure` | 仅当有失败/超时时通知 |

实现：spawn `osascript -e 'display notification …'`（与现状同级，零依赖、零打包）。通知正文为本次 summary 摘要（跑了哪些 step、各自成功/失败/超时）。未来若要点击动作/图标，再走 terminal-notifier 或 .app 路径——本期不做。

---

## 12. 项目布局

```
~/Work/ai/horae/
  go.mod                       module horae
  main.go                      flag 解析 + 子命令分发
  cmd/
    run.go                     run 子命令编排逻辑
    status.go                  status 子命令渲染
  internal/
    recipe/recipe.go           recipes.toml → []Step（go-toml/v2，强类型）
    recipe/duration.go         humantime s/m/h/d/w 解析
    runner/runner.go           os/exec + context + WaitDelay + 进程组 + 超时
    state/state.go             state.toml 读写 + cadence 判定
    notify/notify.go           spawn osascript
    lock/lock.go               flock 单实例
  recipes.toml.example
  deploy/com.user.horae.plist 单 LaunchAgent 模板
  Makefile                     build / install(拷二进制到 ~/.local/bin + 装 plist)
  docs/design.md               本文件
  README.md
```

依赖：标准库 `os/exec`+`context`+`flag`+`log/slog`+`syscall`；唯一外部依赖 `github.com/pelletier/go-toml/v2`（recipe + state 解析）。核心逻辑放 `internal/`、CLI 做薄前端，为未来 TUI（charmbracelet/bubbletea）留门。

---

## 13. 迁移路径（收编现有两组件）

1. 把 brew + npm 写成两条 recipe（npm step 直接复用现有 `~/.local/bin/npm-globals-update.sh`，cadence/SKIP 语义保持）。
2. `make install`：编译二进制到 `~/.local/bin/horae`，装 `com.user.horae` LaunchAgent。
3. `horae run --dry-run` 验证两源被正确识别，再 `horae status` 确认接管。
4. 卸载旧两个 agent：
   - `brew autoupdate delete`（停 homebrew-autoupdate）
   - `launchctl bootout gui/$(id -u)/com.user.npm-globals-autoupdate` + 删旧 plist
5. 旧 npm 日志路径错位问题随旧 agent 卸载一并消失；新工具日志路径单一。

---

## 14. 已定默认值（本设计已拍板，无需再问）

| 决策 | 选择 | 理由 |
|---|---|---|
| CLI 库 | stdlib `flag` | 仅 2 子命令，cobra 过度工程 |
| 状态存储 | `state.toml` 单文件 | 记录极少、人类可读、零依赖（sqlite CGo 破坏单二进制） |
| 日志库 | stdlib `log/slog` | 自带结构化，零依赖 |
| 通知 | spawn osascript | 与现状同级，零打包/签名 |
| launchd 间隔 | 3600s (1h) | 略密于最短 cadence，保证补跑 |
| 默认 cadence | brew 6h / npm 8h | 对齐现状 |
| 默认 timeout | 10m | 覆盖 brew upgrade 大包场景 |
| 默认 notify | on_change | 降噪 |

---

## 15. 实现阶段划分（高层，非工期）

1. **骨架**：go.mod、main + flag 分发、recipe/state 类型与解析（含 duration 解析）、单测。
2. **runner**：os/exec 超时 + 进程组 + PATH 注入 + 捕获，单测（用 `sleep`/`true`/`false` 等可控命令）。
3. **编排 + 状态**：run 串起 cadence 判定 → 执行 → 写 state → summary；`--dry-run`/`--only`/`--skip`/`--force`。
4. **status + 通知 + 锁 + 日志**：status 渲染、osascript 通知、flock、slog 运行日志。
5. **部署 + 迁移**：plist 模板、Makefile install、收编 brew+npm、卸载旧 agent、验收。

每阶段跑 `go vet` + `go test` + `gofmt`；阶段 5 做端到端验收（`horae run --dry-run` → 真跑 → `status` 核对）。

---

## 16. 参考来源

- topgrade（同类先例，step/summary/keep-going/--dry-run 模型）: https://github.com/topgrade-rs/topgrade
- anacron（cadence + 补跑时间戳模型）: https://linux.die.net/man/8/anacron
- Go os/exec 模式与超时（WaitDelay）: https://pkg.go.dev/os/exec · https://github.com/golang/go/issues/22485
- go-toml/v2: https://pkg.go.dev/github.com/pelletier/go-toml/v2
- launchd PATH 坑: https://lucaspin.medium.com/where-is-my-path-launchd-fc3fc5449864
- macOS 通知须从 GUI 会话(LaunchAgent)发: https://github.com/julienXX/terminal-notifier
- Go 1.26 与 Go 1 兼容承诺: https://go.dev/doc/go1.26 · https://go.dev/doc/go1compat
