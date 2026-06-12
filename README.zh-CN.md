<p align="center">
  <img src="assets/logo.svg" width="104" alt="horae logo">
</p>

<p align="center">
  <a href="https://github.com/yaoguohh/horae/releases/latest"><img src="https://img.shields.io/github/v/release/yaoguohh/horae?sort=semver" alt="release"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" alt="platform">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="license"></a>
</p>

# horae

> 一份 TOML recipe + 一个 launchd 触发器，统一 macOS 上所有"敲个命令做更新"的任务。

[English](README.md) · **简体中文**

`horae` 是 macOS 上的轻量更新编排器。各包管理器各有各的自动更新方式——Homebrew 有 tap、npm 要写脚本、pipx / cargo / gcloud 各自为政——结果每个更新器都是一套独立的 launchd agent + 脚本 + 日志约定。`horae` 用**一份 `recipes.toml`** 取而代之：每个更新源声明一次，单个 launchd agent 按各自节奏运行，统一管理 state、日志、通知，外加一个 `status` 视图。

## 为什么

- **现状碎片化**：每个更新器 = 自己的 agent + 脚本 + 日志路径，没有统一的"跑没跑 / 动了啥 / 下次何时"视图。
- **horae**：一份配置、一个触发器、一份日志、一个 `status`。加更新源 = 加一段 `[[step]]`。

## 特性

- **声明式 recipe** —— 每个更新源是 `recipes.toml` 里的一个 `[[step]]`（command 或 shell、cadence、timeout、env）。
- **单 launchd 触发器** —— 一个 LaunchAgent 每小时唤起；每个源按自己的 `cadence` 运行（anacron 式）。
- **睡眠 / 关机补跑** —— 是否到期看"距上次成功多久"，错过的源开机后自动补跑，不依赖 launchd 自身的补跑。
- **失败退避** —— 持续失败的源按 cadence 重试，而非每次都跑（不刷屏通知）。
- **安全的子进程执行** —— 每步超时、整进程组 kill（交互式更新器不会卡死）、有界输出捕获。
- **统一可观测性** —— `status` 看每源状态，按天的结构化日志，失败带 stderr 尾部。
- **原生通知** —— 经 `osascript` 发 macOS 通知，策略 `always` / `on_change` / `on_failure` / `never`。
- **菜单栏 app（可选）** —— SwiftUI 前端：实时进度、每源状态、内置日志查看、源管理，经 [Sparkle](https://sparkle-project.org) 自更新。
- **单静态二进制** —— Go，标准库 + 一个 TOML 库，近乎零运行时依赖。装一次跑数年。

## 环境要求

- **macOS**（依赖 launchd；Apple Silicon 或 Intel）。
- 从源码构建：**Go 1.26+**。开发：`golangci-lint`（可选）。

## 安装

```bash
git clone https://github.com/yaoguohh/horae.git
cd horae
cp recipes.toml.example ~/.config/horae/recipes.toml   # 然后按需编辑
make install   # 编译二进制 → ~/.local/bin，生成并加载 LaunchAgent
```

`make install` 会把你的 `$HOME` 代入 LaunchAgent plist，因此对任何用户都适用。

- 停止调度：`launchctl bootout gui/$(id -u)/com.user.horae`
- 彻底卸载：`make uninstall`

## 菜单栏 app

`horae` 附带一个可选的 SwiftUI 菜单栏 app —— 基于同一套引擎与文件契约的轻量前端（以读为主）。它在更新时显示实时进度、每源状态弹窗、内置日志查看器、源管理（从预设增删，或直接编辑 recipe），并接管原生通知。引擎与 LaunchAgent 始终是主导，app 不会变成硬依赖。

从 [最新 release](https://github.com/yaoguohh/horae/releases/latest) 下载 `Horae.dmg`，打开后把 **Horae** 拖进"应用程序"。首次启动右键 → 打开 一次以放行 Gatekeeper（app 为 ad-hoc 签名、未公证）。或从源码构建：

```bash
make app           # 构建 Horae.app（release + 内嵌 Sparkle，ad-hoc 签名）
make install-app   # 构建 + 拷贝到 ~/Applications
```

app 读写同一份 `~/.config/horae/recipes.toml`，所以也要装好引擎（`make install`）—— app 是前端，不是替代品。

**自动更新。** app 经 [Sparkle](https://sparkle-project.org) 自更新：后台检查 appcast，也可在 设置 → 软件更新 手动检查。更新用 Sparkle 的 EdDSA 签名校验，无需 Apple 公证。

## 快速开始

一份最小 `recipes.toml`：

```toml
[defaults]
timeout = "15m"
notify  = "on_change"   # always | never | on_change | on_failure

[[step]]
id      = "brew"
label   = "Homebrew"
cadence = "3h"
shell   = "brew update && brew upgrade && brew cleanup"

[[step]]
id      = "npm-globals"
label   = "npm globals"
cadence = "3h"
shell   = "npx npm-check-updates -g -u && npm update -g"
```

```bash
horae run --dry-run   # 只打印会跑什么，不执行
horae run --force     # 立刻全部更新
horae status          # 每源上次结果 + 距下次到期
```

## 命令

| 命令 | 说明 |
|---|---|
| `horae run` | 跑所有到期源（launchd 调用的就是这个） |
| `horae run --force` | 立刻跑所有启用的源，忽略 cadence |
| `horae run --only a,b` | 只跑这些源，忽略 cadence |
| `horae run --skip a,b` | 跑除这些外的到期源 |
| `horae run --dry-run` | 只打印会跑什么，不执行 |
| `horae status` | 渲染每源状态表 |
| `horae run --config PATH` | 用其他 recipe 路径 |

`--only` / `--skip` 传不存在的 id 会非零退出（防拼写错被静默吞掉）。

## 配置

recipe 位于 `~/.config/horae/recipes.toml`（支持 `$XDG_CONFIG_HOME`）。

| 字段 | 说明 |
|---|---|
| `[defaults].timeout` | step 默认超时（默认 `10m`） |
| `[defaults].notify` | `always` / `never` / `on_change` / `on_failure` |
| `[[step]].id` | 唯一标识，state 与日志按它索引 |
| `[[step]].label` | 显示名（缺省回落到 id） |
| `[[step]].cadence` | 期望频率：`s` / `m` / `h` / `d` / `w`（如 `3h`、`1d`、`7d`） |
| `[[step]].command` | argv 数组，不起 shell（与 shell 二选一） |
| `[[step]].shell` | shell 片段，需 `&&` / 管道时用 |
| `[[step]].timeout` | 覆盖默认超时 |
| `[[step]].env` | 追加 / 覆盖环境变量（如注入 PATH） |
| `[[step]].enabled` | `false` = 永不跑（占位）；缺省 `true` |

**PATH 说明：** launchd 下 PATH 近乎空。horae 前置 `/opt/homebrew/bin` 并按注入的 PATH 解析裸命令。二进制在标准目录外（如 `~/.local/bin`、`~/.cargo/bin`）时，用绝对路径或给 step 设 `env.PATH`。

| 用途 | 路径 |
|---|---|
| 配置 | `~/.config/horae/recipes.toml` |
| 状态（status 数据源） | `~/.local/state/horae/state.toml` |
| 运行日志（按天） | `~/Library/Logs/horae/run-YYYYMMDD.log` |
| 二进制 / 调度 | `~/.local/bin/horae` / `~/Library/LaunchAgents/com.user.horae.plist` |

## 工作原理

触发频率与"某源是否该跑"是解耦的：

- 单个 LaunchAgent 每小时唤起 `horae run`（`StartInterval`）。
- 对每个 step，horae 比较 `now - 上次成功 >= cadence`。`cadence = "3h"` 的源即便触发器每小时一次，也大致每 3h 跑一次。
- 因为到期判定基于"距上次成功多久"（anacron 式，而非固定时刻），睡眠或关机的机器开机后自动补跑过期的源——补跑无需特殊调度支持。
- 单实例文件锁防止重叠运行；撞锁的那次干净退出，不计为失败。

借鉴 [topgrade](https://github.com/topgrade-rs/topgrade)（step + summary 模型）与 `anacron`（cadence + 时间戳补跑）。

## 从 homebrew-autoupdate 迁移

```bash
# horae 装好并确认接管后：
brew autoupdate delete
brew untap homebrew/autoupdate   # delete 只删 agent 不卸 tap；残留 tap 会让 brew update 失败
```

## 开发

```bash
make check   # go vet + golangci-lint + go test
make fmt     # gofumpt + goimports
```

架构说明见 [docs/design.md](docs/design.md)。

## 许可证

[MIT](LICENSE)。
