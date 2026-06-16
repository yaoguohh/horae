package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"horae/internal/control"
	"horae/internal/lock"
	"horae/internal/logs"
	"horae/internal/orchestrator"
	"horae/internal/paths"
	"horae/internal/recipe"
	"horae/internal/report"
	"horae/internal/runner"
	"horae/internal/state"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	switch os.Args[1] {
	case "run":
		os.Exit(cmdRun(os.Args[2:]))
	case "status":
		os.Exit(cmdStatus(os.Args[2:]))
	case "config":
		os.Exit(cmdConfig(os.Args[2:]))
	case "-h", "--help", "help":
		usage()
		os.Exit(0)
	default:
		fmt.Fprintf(os.Stderr, "未知子命令: %s\n", os.Args[1])
		usage()
		os.Exit(2)
	}
}

func usage() {
	fmt.Fprint(os.Stderr, `horae — 统一更新编排器

用法:
  horae run     [--config PATH] [--only a,b] [--skip a,b] [--force] [--dry-run]
  horae status  [--config PATH] [--json]
`)
}

func cmdRun(args []string) int {
	fs := flag.NewFlagSet("run", flag.ExitOnError)
	cfg := fs.String("config", paths.Config(), "recipe 路径")
	onlyFlag := fs.String("only", "", "只跑这些 step（逗号分隔，忽略 cadence）")
	skipFlag := fs.String("skip", "", "跳过这些 step（逗号分隔）")
	force := fs.Bool("force", false, "忽略 cadence 跑所有启用的 step")
	dryRun := fs.Bool("dry-run", false, "只打印会跑什么，不执行")
	_ = fs.Parse(args) // flag.ExitOnError：解析失败直接退出，返回值恒为 nil

	rec, err := loadEffectiveRecipe(*cfg)
	if err != nil {
		fmt.Fprintln(os.Stderr, "加载 recipe 失败:", err)
		return 1
	}
	onlyIDs, skipIDs := splitCSV(*onlyFlag), splitCSV(*skipFlag)
	// 显式失败拼写错误的 step id，避免静默空跑 + exit 0 掩盖意图。
	if unknown := unknownIDs(rec, append(append([]string{}, onlyIDs...), skipIDs...)); len(unknown) > 0 {
		fmt.Fprintf(os.Stderr, "--only/--skip 中未知 step: %s\n", strings.Join(unknown, ", "))
		return 2
	}

	logger := newLogger()
	if !*dryRun {
		release, code, ok := acquireLock(logger)
		if !ok {
			return code
		}
		defer release()
	}

	st, err := state.Load(paths.State())
	if err != nil {
		fmt.Fprintln(os.Stderr, "加载 state 失败:", err)
		return 1
	}

	opts := orchestrator.Options{
		Only: onlyIDs, Skip: skipIDs, Force: *force, DryRun: *dryRun,
		Paused: loadPause().Active(time.Now()),
	}
	results, newSt := orchestrator.Run(rec, st, runDeps(logger, *dryRun), opts)
	reportResults(logger, results, *dryRun)
	if *dryRun {
		return 0
	}
	if err := state.Save(paths.State(), newSt); err != nil {
		fmt.Fprintln(os.Stderr, "写 state 失败:", err)
		return 1
	}
	finishRun(logger, results, rec.Defaults.Notify)
	return exitCode(results)
}

// loadEffectiveRecipe 加载 recipe 并叠加 app 写的 overrides（enabled）。
func loadEffectiveRecipe(cfg string) (recipe.Recipe, error) {
	rec, err := recipe.Load(cfg)
	if err != nil {
		return recipe.Recipe{}, err
	}
	ov, err := control.LoadOverrides(paths.Overrides())
	if err != nil {
		return recipe.Recipe{}, fmt.Errorf("load overrides: %w", err)
	}
	rec.Steps = ov.Apply(rec.Steps)
	return rec, nil
}

// loadPause 读全局暂停；文件损坏不应阻断更新，视为未暂停。
func loadPause() control.Pause {
	p, err := control.LoadPause(paths.Pause())
	if err != nil {
		return control.Pause{}
	}
	return p
}

// acquireLock 取单实例锁。ok=false 时调用方按 code 退出（撞锁→0，错误→1）。
func acquireLock(logger *slog.Logger) (release func(), code int, ok bool) {
	l, err := lock.Acquire(paths.Lock())
	if errors.Is(err, lock.ErrLocked) {
		// 上一轮还在跑不是故障，正常退出，避免 launchd 把每次撞锁记成失败 run。
		fmt.Fprintln(os.Stderr, "上一轮 horae 仍在运行，跳过本次")
		return nil, 0, false
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "获取锁失败:", err)
		return nil, 1, false
	}
	return func() {
		if err := l.Release(); err != nil {
			logger.Warn("释放锁失败", "err", err)
		}
	}, 0, true
}

// runDeps 组装编排依赖。非 dry-run 时挂上逐步落盘 + 实时进度写出钩子。
func runDeps(logger *slog.Logger, dryRun bool) orchestrator.Deps {
	deps := orchestrator.Deps{
		Runner:   runner.ExecRunner{},
		Now:      time.Now,
		BasePATH: runner.DefaultPATH(),
	}
	if dryRun {
		return deps
	}
	// 逐步落盘：长 run 中途被 launchd SIGKILL 也不丢已完成 step 的成功时间戳。
	deps.OnStepDone = func(s state.State) {
		if err := state.Save(paths.State(), s); err != nil {
			logger.Error("逐步落盘失败", "err", err)
		}
	}
	// 实时进度：step 开始写 current.json；子进程每产出一行(节流)更新 LastLine，菜单栏 app 据此显示实时输出。
	cw := newCurrentWriter(paths.Current(), logger)
	deps.OnStepStart = cw.start
	deps.Runner = runner.ExecRunner{OnLine: cw.line}
	return deps
}

// finishRun 收尾：清实时进度 + 写最近结果（含通知决策，供菜单栏 app 发原生通知）。
func finishRun(logger *slog.Logger, results []orchestrator.StepResult, policy string) {
	if err := report.ClearCurrent(paths.Current()); err != nil {
		logger.Warn("清 current.json 失败", "err", err)
	}
	if policy == "" {
		policy = "on_change"
	}
	if err := report.WriteLastRun(paths.LastRun(), report.Build(results, policy, time.Now())); err != nil {
		logger.Warn("写 last-run.json 失败", "err", err)
	}
	// 日志轮转：只留近 14 天，旧的自动删。
	if err := logs.Prune(paths.LogDir(), 14, time.Now()); err != nil {
		logger.Warn("日志清理失败", "err", err)
	}
}

// reportResults 打印每个 step 结果到终端，并写结构化运行日志（失败/超时附 stderr 尾部）。
func reportResults(logger *slog.Logger, results []orchestrator.StepResult, dryRun bool) {
	for _, r := range results {
		printResult(r, dryRun)
		attrs := []any{
			"id", r.Step.ID,
			"status", string(r.Status),
			"exit", r.ExitCode,
			"duration", r.Duration.Round(time.Second).String(),
			"reason", r.Reason,
		}
		if r.Status == state.StatusFailure || r.Status == state.StatusTimeout {
			attrs = append(attrs, "stderr_tail", r.StderrTail)
		}
		logger.Info("step", attrs...)
	}
}

// unknownIDs 返回 ids 中不存在于 recipe 的 step id（用于校验 --only/--skip 拼写）。
func unknownIDs(rec recipe.Recipe, ids []string) []string {
	valid := make(map[string]bool, len(rec.Steps))
	for _, s := range rec.Steps {
		valid[s.ID] = true
	}
	var unknown []string
	for _, id := range ids {
		if !valid[id] {
			unknown = append(unknown, id)
		}
	}
	return unknown
}

func cmdStatus(args []string) int {
	fs := flag.NewFlagSet("status", flag.ExitOnError)
	cfg := fs.String("config", paths.Config(), "recipe 路径")
	asJSON := fs.Bool("json", false, "输出 JSON（供菜单栏 app 消费）")
	_ = fs.Parse(args) // flag.ExitOnError：解析失败直接退出，返回值恒为 nil

	rec, err := loadEffectiveRecipe(*cfg)
	if err != nil {
		fmt.Fprintln(os.Stderr, "加载 recipe 失败:", err)
		return 1
	}
	st, err := state.Load(paths.State())
	if err != nil {
		fmt.Fprintln(os.Stderr, "加载 state 失败:", err)
		return 1
	}
	now := time.Now()
	if *asJSON {
		return printStatusJSON(rec, st, now)
	}
	fmt.Print(orchestrator.RenderStatus(rec, st, now))
	return 0
}

func printStatusJSON(rec recipe.Recipe, st state.State, now time.Time) int {
	view := report.BuildStatus(rec, st, loadPause(), now)
	data, err := json.MarshalIndent(view, "", "  ")
	if err != nil {
		fmt.Fprintln(os.Stderr, "编码 status JSON 失败:", err)
		return 1
	}
	fmt.Println(string(data))
	return 0
}

func printResult(r orchestrator.StepResult, dryRun bool) {
	switch {
	case dryRun && r.WouldRun:
		fmt.Printf("[会跑] %s\n", r.Step.DisplayName())
	case dryRun:
		fmt.Printf("[跳过] %s（%s）\n", r.Step.DisplayName(), r.Reason)
	case r.Status == state.StatusSkipped:
		fmt.Printf("[跳过] %s（%s）\n", r.Step.DisplayName(), r.Reason)
	default:
		fmt.Printf("[%s] %s（%s）\n", r.Status, r.Step.DisplayName(), r.Duration.Round(time.Second))
	}
}

func exitCode(results []orchestrator.StepResult) int {
	for _, r := range results {
		if r.Status == state.StatusFailure || r.Status == state.StatusTimeout {
			return 1
		}
	}
	return 0
}

func splitCSV(s string) []string {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	var out []string
	for _, p := range strings.Split(s, ",") {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}

func newLogger() *slog.Logger {
	path := paths.Log()
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return slog.New(slog.NewTextHandler(io.Discard, nil))
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return slog.New(slog.NewTextHandler(io.Discard, nil))
	}
	return slog.New(slog.NewTextHandler(f, &slog.HandlerOptions{Level: slog.LevelInfo}))
}
