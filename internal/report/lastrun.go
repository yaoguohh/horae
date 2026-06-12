package report

import (
	"horae/internal/orchestrator"
	"horae/internal/state"
	"time"
)

// Change 是一个包级变更(二期由 per-step 解析填充；一期恒为空)。
type Change struct {
	Name string `json:"name"`
	From string `json:"from,omitempty"`
	To   string `json:"to,omitempty"`
}

// StepReport 是单个执行过的 step 的结果(跳过的 step 不入此列表)。
type StepReport struct {
	ID         string   `json:"id"`
	Label      string   `json:"label"`
	Status     string   `json:"status"`
	ExitCode   int      `json:"exit_code"`
	Duration   string   `json:"duration"`
	Changes    []Change `json:"changes"`
	OutputTail string   `json:"output_tail,omitempty"`
}

// Summary 是本轮各结果计数。Ran = OK + Failed + Timeout。
type Summary struct {
	Ran     int `json:"ran"`
	OK      int `json:"ok"`
	Failed  int `json:"failed"`
	Timeout int `json:"timeout"`
	Skipped int `json:"skipped"`
}

// LastRun 是最近一次 run 的结果 + 通知决策(last-run.json)。
// ShouldNotify 由引擎按 notify 策略算好，app 只需照此发原生通知，不重复实现策略。
type LastRun struct {
	FinishedAt   time.Time    `json:"finished_at"`
	NotifyPolicy string       `json:"notify_policy"`
	ShouldNotify bool         `json:"should_notify"`
	Summary      Summary      `json:"summary"`
	Steps        []StepReport `json:"steps"`
}

// Build 从一轮 run 的结果构建 LastRun。跳过的 step 只计入 Summary.Skipped，不入 Steps。
func Build(results []orchestrator.StepResult, policy string, now time.Time) LastRun {
	lr := LastRun{
		FinishedAt:   now,
		NotifyPolicy: policy,
		ShouldNotify: orchestrator.ShouldNotify(policy, results),
		Steps:        []StepReport{},
	}
	for _, r := range results {
		switch r.Status {
		case state.StatusSuccess:
			lr.Summary.Ran++
			lr.Summary.OK++
		case state.StatusFailure:
			lr.Summary.Ran++
			lr.Summary.Failed++
		case state.StatusTimeout:
			lr.Summary.Ran++
			lr.Summary.Timeout++
		case state.StatusSkipped:
			lr.Summary.Skipped++
			continue
		default:
			continue
		}
		lr.Steps = append(lr.Steps, StepReport{
			ID:         r.Step.ID,
			Label:      r.Step.DisplayName(),
			Status:     string(r.Status),
			ExitCode:   r.ExitCode,
			Duration:   r.Duration.Round(time.Second).String(),
			Changes:    []Change{},
			OutputTail: r.StderrTail,
		})
	}
	return lr
}

// WriteLastRun 写最近结果。
func WriteLastRun(path string, lr LastRun) error { return writeJSON(path, lr) }
