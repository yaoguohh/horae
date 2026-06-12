package report

import (
	"horae/internal/control"
	"horae/internal/recipe"
	"horae/internal/state"
	"time"
)

// SourceView 是 status --json 中单个源的合成视图(recipe + state)。
// Enabled 已反映 overrides(调用方在传入前应用过 overrides)。
type SourceView struct {
	ID            string     `json:"id"`
	Label         string     `json:"label"`
	Enabled       bool       `json:"enabled"`
	Status        string     `json:"status"`
	LastSuccessAt *time.Time `json:"last_success_at,omitempty"`
	LastDuration  string     `json:"last_duration,omitempty"`
	LastExitCode  int        `json:"last_exit_code"`
	NextDueAt     *time.Time `json:"next_due_at,omitempty"`
	Due           bool       `json:"due"`
}

// StatusView 是 status --json 的顶层视图，菜单栏 app 渲染卡片的主数据源。
type StatusView struct {
	GeneratedAt time.Time    `json:"generated_at"`
	Paused      bool         `json:"paused"`
	PausedUntil *time.Time   `json:"paused_until,omitempty"`
	Sources     []SourceView `json:"sources"`
}

// BuildStatus 合成 status 视图。step.IsEnabled 应已含 overrides。
func BuildStatus(rec recipe.Recipe, st state.State, pause control.Pause, now time.Time) StatusView {
	view := StatusView{GeneratedAt: now, Paused: pause.Active(now), Sources: []SourceView{}}
	if view.Paused && pause.Until != nil {
		view.PausedUntil = pause.Until
	}
	for _, step := range rec.Steps {
		e := st[step.ID]
		s := SourceView{
			ID:           step.ID,
			Label:        step.DisplayName(),
			Enabled:      step.IsEnabled(),
			Status:       "never",
			LastDuration: e.LastDuration,
			LastExitCode: e.LastExitCode,
			Due:          step.IsEnabled() && state.IsDue(e, step.Cadence.Std(), now),
		}
		if e.LastStatus != "" {
			s.Status = string(e.LastStatus)
		}
		if !e.LastSuccessAt.IsZero() {
			t := e.LastSuccessAt
			s.LastSuccessAt = &t
		}
		if nd, ok := state.NextDue(e, step.Cadence.Std()); ok {
			s.NextDueAt = &nd
		}
		view.Sources = append(view.Sources, s)
	}
	return view
}
