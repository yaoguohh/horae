package orchestrator

import (
	"context"
	"horae/internal/recipe"
	"horae/internal/runner"
	"horae/internal/state"
	"slices"
	"time"
)

type Deps struct {
	Runner   runner.Runner
	Now      func() time.Time
	BasePATH string
	// OnStepDone 在每个执行过的 step 写回内存 state 后调用（可选）。
	// 用于逐步落盘：长 run 中途被 launchd SIGKILL（登出/关机）也不丢已完成的成功时间戳。
	OnStepDone func(state.State)
	// OnStepStart 在每个将执行的 step 开始前调用（可选；index 从 1 计，total=本轮将执行步数）。
	// 用于写实时进度文件，供菜单栏 app 显示“正在更新 X”。
	OnStepStart func(id, label string, index, total int)
}

type Options struct {
	Only   []string
	Skip   []string
	Force  bool
	DryRun bool
	// Paused：全局暂停。仅阻断 cadence 驱动的自动跑；--force / --only 显式触发不受影响。
	Paused bool
}

type StepResult struct {
	Step       recipe.Step
	Status     state.Status // success/failure/timeout/skipped
	ExitCode   int
	Duration   time.Duration
	WouldRun   bool   // 仅 dry-run：本次会跑
	Reason     string // 跳过原因（disabled / 未到期 / --skip / --only）
	StderrTail string // 子进程 stderr 尾部（有界），失败/超时时供日志诊断
}

// Run 遍历 step，按 cadence/选项决定执行，返回每步结果与更新后的 state（纯函数：state in→out）。
func Run(rec recipe.Recipe, st state.State, deps Deps, opts Options) ([]StepResult, state.State) {
	now := deps.Now()
	defaultTimeout := rec.Defaults.Timeout.Std()
	if defaultTimeout <= 0 {
		defaultTimeout = 10 * time.Minute
	}
	newSt := cloneState(st)
	pruneOrphans(newSt, rec.Steps)
	total := runnableCount(rec.Steps, newSt, opts, now)
	idx := 0
	var results []StepResult

	for _, step := range rec.Steps {
		entry := newSt[step.ID]
		r := StepResult{Step: step}

		if reason := skipReason(step, entry, opts, now); reason != "" {
			r.Status, r.Reason = state.StatusSkipped, reason
			results = append(results, r)
			continue
		}
		if opts.DryRun {
			r.WouldRun = true
			results = append(results, r)
			continue
		}

		idx++
		if deps.OnStepStart != nil {
			deps.OnStepStart(step.ID, step.DisplayName(), idx, total)
		}
		res := deps.Runner.Run(context.Background(), step, defaultTimeout, deps.BasePATH)
		r.ExitCode, r.Duration, r.StderrTail = res.ExitCode, res.Duration, res.Stderr
		entry.LastAttemptAt = now
		entry.LastExitCode = res.ExitCode
		entry.LastDuration = res.Duration.Round(time.Second).String()
		switch res.Outcome {
		case runner.OutcomeSuccess:
			entry.LastStatus, entry.LastSuccessAt = state.StatusSuccess, now
			r.Status = state.StatusSuccess
		case runner.OutcomeTimeout:
			entry.LastStatus = state.StatusTimeout
			r.Status = state.StatusTimeout
		default:
			entry.LastStatus = state.StatusFailure
			r.Status = state.StatusFailure
		}
		newSt[step.ID] = entry
		if deps.OnStepDone != nil {
			deps.OnStepDone(newSt)
		}
		results = append(results, r)
	}
	return results, newSt
}

// skipReason 返回该 step 本次应跳过的原因；返回空串表示应执行。
func skipReason(step recipe.Step, entry state.Entry, opts Options, now time.Time) string {
	if !step.IsEnabled() {
		// disabled 优先于 --only（enabled=false 表示永不跑）；被 --only 点名时升级提示，
		// 避免“--only 了却什么都没发生”的困惑。
		if len(opts.Only) > 0 && slices.Contains(opts.Only, step.ID) {
			return "--only 命中但该 step 已禁用，未执行"
		}
		return "未启用"
	}
	if len(opts.Only) > 0 && !slices.Contains(opts.Only, step.ID) {
		return "不在 --only 内"
	}
	if slices.Contains(opts.Skip, step.ID) {
		return "--skip"
	}
	// --force 或 --only 点名 → 显式触发，忽略 cadence 与全局暂停立即跑。
	if opts.Force || len(opts.Only) > 0 {
		return ""
	}
	// 全局暂停只阻断 cadence 驱动的自动跑（上面的显式触发已放行）。
	if opts.Paused {
		return "已暂停"
	}
	if state.IsDue(entry, step.Cadence.Std(), now) {
		return ""
	}
	return "未到期"
}

// runnableCount 预扫描本轮将真正执行的 step 数（供 OnStepStart 的 total）。
func runnableCount(steps []recipe.Step, st state.State, opts Options, now time.Time) int {
	if opts.DryRun {
		return 0
	}
	n := 0
	for _, step := range steps {
		if skipReason(step, st[step.ID], opts, now) == "" {
			n++
		}
	}
	return n
}

func cloneState(s state.State) state.State {
	out := make(state.State, len(s))
	for k, v := range s {
		out[k] = v
	}
	return out
}

// pruneOrphans 删除 recipe 中已不存在的 step 的 state 条目，避免陈旧记录长期堆积。
func pruneOrphans(s state.State, steps []recipe.Step) {
	want := make(map[string]bool, len(steps))
	for _, st := range steps {
		want[st.ID] = true
	}
	for id := range s {
		if !want[id] {
			delete(s, id)
		}
	}
}
