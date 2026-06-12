# horae

统一更新编排器。一份 TOML recipe 描述所有"命令式更新源"，单个 launchd 触发器驱动，按各源 cadence（anacron 式 + 睡眠补跑）执行，统一 state/日志/通知 + `status` 子命令。

设计与取舍见 `docs/design.md`，实现计划见 `docs/plan.md`。

## 结构

```
main.go                  CLI 前端（flag 子命令分发：run / status）
internal/
  recipe/                recipes.toml → 强类型 Step + duration 解析
  state/                 state.toml 读写（原子）+ cadence 判定（IsDue/NextDue）
  runner/                os/exec 子进程执行（超时/进程组/PATH 解析/有界捕获）
  orchestrator/          编排（cadence/force/only/skip/dry-run）+ summary/status 渲染
  notify/ lock/ paths/   osascript 通知 / flock 单实例 / XDG+Logs 路径
deploy/com.user.horae.plist   单 LaunchAgent 模板
```

## 验证

- 开发门禁：`make check`（= `go vet` + `golangci-lint run` + `go test`）。**提交 / 合并前必过。**
- 格式化：`make fmt`（gofumpt + goimports）。
- 单包快测：`go test ./internal/<pkg>/ -v`。

## 原则

- 不写占位代码 / MVP / TODO 注释 / 半成品 / 兼容性僵尸代码。
- 根因优先：先确认根因再修，不修中间症状。
- 工具优先：stdlib 与经过验证的库 > 自造轮子（本项目唯一外部依赖 go-toml/v2，其余全 stdlib）。
- 依赖注入优先：依赖通过接口注入（如 `runner.Runner` / `notify.Notifier` / `Deps.Now`），核心逻辑可用 fake 确定性单测。

## 代码

- 函数 ≤ 80 行 / 圈复杂度 ≤ 15 / 嵌套 ≤ 3 层 —— 由 `.golangci.yml`（funlen/gocyclo/nestif）机器化拦截。
- 错误必检（errcheck）；包装用 `fmt.Errorf("...: %w", err)`；比较用 `errors.Is/As`。
- 注释只写 WHY（非显而易见处）；**禁用 emoji**（代码 / 字符串 / 注释全禁）。
- 接口定义在消费方；类型/方法签名保持跨文件一致。
- 用户私有文件（state/lock/log）权限 0600，目录 0700。

## 测试

- TDD：先写失败测试，再实现。
- 单测 60s 内跑完；子进程测试用 `true`/`false`/`sleep`/临时脚本等可控命令。
- 注入接口 + 固定 `now` 做确定性断言，不依赖 wall-clock / 真实更新器。

## 提交

格式 `<type>(<scope>): <标题>`，type ∈ feat/fix/refactor/test/docs/chore；scope = 包名（recipe/state/runner/orchestrator/notify/lock/paths）或省略（跨包）。

- 标题聚焦 why 而非 what。
- **禁止 Co-Authored-By 签名。**
- 不主动 `git push`（push / squash 节奏由用户控制）。

## 质量门禁哲学

便宜的检查跑得勤、贵的检查跑得稀：编辑器 LSP 实时 → 写完一组改动跑 `make check` → 合 main 前再跑一次。架构 / 设计层面的批量审查走全局 `enforcing-code-standards` skill（本项目不需要项目特化 skill）。

## codegraph

仓内已 `codegraph init`。写 / 改代码前先用 codegraph 查符号与调用关系（`codegraph context <task>` / `callers` / `callees`），别盲改。索引随文件变更需 `codegraph sync`。
