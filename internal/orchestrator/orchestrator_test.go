package orchestrator

import (
	"context"
	"horae/internal/recipe"
	"horae/internal/runner"
	"horae/internal/state"
	"strings"
	"testing"
	"time"
)

type fakeRunner struct {
	ran    []string
	result runner.Result
}

func (f *fakeRunner) Run(_ context.Context, step recipe.Step, _ time.Duration, _ string) runner.Result {
	f.ran = append(f.ran, step.ID)
	return f.result
}

func step(id, cadence string, enabled bool) recipe.Step {
	d, _ := recipe.ParseDuration(cadence)
	e := enabled
	return recipe.Step{ID: id, Cadence: recipe.Duration(d), Command: []string{"true"}, Enabled: &e}
}

func TestRunSkipsNotDue(t *testing.T) {
	now := time.Date(2026, 5, 29, 12, 0, 0, 0, time.UTC)
	rec := recipe.Recipe{Steps: []recipe.Step{step("brew", "6h", true)}}
	st := state.State{"brew": {LastSuccessAt: now.Add(-1 * time.Hour), LastStatus: state.StatusSuccess}}
	fr := &fakeRunner{result: runner.Result{Outcome: runner.OutcomeSuccess}}
	results, _ := Run(rec, st, Deps{Runner: fr, Now: func() time.Time { return now }}, Options{})
	if len(fr.ran) != 0 {
		t.Errorf("should skip not-due step, ran=%v", fr.ran)
	}
	if results[0].Status != state.StatusSkipped {
		t.Errorf("status = %v, want skipped", results[0].Status)
	}
}

func TestRunRunsDueAndUpdatesState(t *testing.T) {
	now := time.Date(2026, 5, 29, 12, 0, 0, 0, time.UTC)
	rec := recipe.Recipe{Steps: []recipe.Step{step("brew", "6h", true)}}
	st := state.State{"brew": {LastSuccessAt: now.Add(-7 * time.Hour)}}
	fr := &fakeRunner{result: runner.Result{Outcome: runner.OutcomeSuccess, ExitCode: 0, Duration: 41 * time.Second}}
	results, newSt := Run(rec, st, Deps{Runner: fr, Now: func() time.Time { return now }}, Options{})
	if len(fr.ran) != 1 || fr.ran[0] != "brew" {
		t.Errorf("should run due step, ran=%v", fr.ran)
	}
	if results[0].Status != state.StatusSuccess {
		t.Errorf("status = %v", results[0].Status)
	}
	if !newSt["brew"].LastSuccessAt.Equal(now) {
		t.Errorf("last_success_at not updated: %v", newSt["brew"].LastSuccessAt)
	}
}

func TestRunFailureDoesNotUpdateSuccess(t *testing.T) {
	now := time.Date(2026, 5, 29, 12, 0, 0, 0, time.UTC)
	prevSuccess := now.Add(-7 * time.Hour)
	rec := recipe.Recipe{Steps: []recipe.Step{step("brew", "6h", true)}}
	st := state.State{"brew": {LastSuccessAt: prevSuccess}}
	fr := &fakeRunner{result: runner.Result{Outcome: runner.OutcomeFailure, ExitCode: 1}}
	_, newSt := Run(rec, st, Deps{Runner: fr, Now: func() time.Time { return now }}, Options{})
	if !newSt["brew"].LastSuccessAt.Equal(prevSuccess) {
		t.Error("failure must NOT update last_success_at")
	}
	if newSt["brew"].LastStatus != state.StatusFailure || !newSt["brew"].LastAttemptAt.Equal(now) {
		t.Errorf("failure should update attempt+status: %+v", newSt["brew"])
	}
}

func TestRunDisabledSkipped(t *testing.T) {
	now := time.Now()
	rec := recipe.Recipe{Steps: []recipe.Step{step("brew", "6h", false)}}
	fr := &fakeRunner{}
	Run(rec, state.State{}, Deps{Runner: fr, Now: func() time.Time { return now }}, Options{})
	if len(fr.ran) != 0 {
		t.Errorf("disabled step must not run, ran=%v", fr.ran)
	}
}

func TestRunForceIgnoresCadence(t *testing.T) {
	now := time.Now()
	rec := recipe.Recipe{Steps: []recipe.Step{step("brew", "6h", true)}}
	st := state.State{"brew": {LastSuccessAt: now}}
	fr := &fakeRunner{result: runner.Result{Outcome: runner.OutcomeSuccess}}
	Run(rec, st, Deps{Runner: fr, Now: func() time.Time { return now }}, Options{Force: true})
	if len(fr.ran) != 1 {
		t.Errorf("force should run regardless of cadence, ran=%v", fr.ran)
	}
}

func TestRunOnlyFilter(t *testing.T) {
	now := time.Now()
	rec := recipe.Recipe{Steps: []recipe.Step{step("brew", "6h", true), step("npm", "6h", true)}}
	fr := &fakeRunner{result: runner.Result{Outcome: runner.OutcomeSuccess}}
	Run(rec, state.State{}, Deps{Runner: fr, Now: func() time.Time { return now }}, Options{Only: []string{"npm"}})
	if len(fr.ran) != 1 || fr.ran[0] != "npm" {
		t.Errorf("only filter failed, ran=%v", fr.ran)
	}
}

func TestRunDryRunDoesNotExecute(t *testing.T) {
	now := time.Now()
	rec := recipe.Recipe{Steps: []recipe.Step{step("brew", "6h", true)}}
	fr := &fakeRunner{}
	results, _ := Run(rec, state.State{}, Deps{Runner: fr, Now: func() time.Time { return now }}, Options{DryRun: true})
	if len(fr.ran) != 0 {
		t.Error("dry-run must not execute")
	}
	if !results[0].WouldRun {
		t.Error("dry-run should mark due step as WouldRun")
	}
}

func TestRunPrunesOrphanState(t *testing.T) {
	now := time.Now()
	rec := recipe.Recipe{Steps: []recipe.Step{step("brew", "6h", true)}}
	st := state.State{
		"brew":     {LastSuccessAt: now},
		"old-gone": {LastSuccessAt: now}, // recipe 里已删除
	}
	fr := &fakeRunner{result: runner.Result{Outcome: runner.OutcomeSuccess}}
	_, newSt := Run(rec, st, Deps{Runner: fr, Now: func() time.Time { return now }}, Options{})
	if _, ok := newSt["old-gone"]; ok {
		t.Error("orphan entry should be pruned")
	}
	if _, ok := newSt["brew"]; !ok {
		t.Error("existing step entry must remain")
	}
}

func TestRunOnlyHitDisabledStepReason(t *testing.T) {
	now := time.Now()
	rec := recipe.Recipe{Steps: []recipe.Step{step("pipx", "6h", false)}}
	fr := &fakeRunner{}
	results, _ := Run(rec, state.State{}, Deps{Runner: fr, Now: func() time.Time { return now }}, Options{Only: []string{"pipx"}})
	if len(fr.ran) != 0 {
		t.Error("disabled step must not run even if in --only")
	}
	if !strings.Contains(results[0].Reason, "禁用") {
		t.Errorf("reason should explain disabled, got %q", results[0].Reason)
	}
}

func TestRunOnStepDoneFiresPerRunStep(t *testing.T) {
	now := time.Now()
	rec := recipe.Recipe{Steps: []recipe.Step{step("a", "6h", true), step("b", "6h", true)}}
	fr := &fakeRunner{result: runner.Result{Outcome: runner.OutcomeSuccess}}
	calls := 0
	Run(rec, state.State{}, Deps{Runner: fr, Now: func() time.Time { return now }, OnStepDone: func(state.State) { calls++ }}, Options{})
	if calls != 2 {
		t.Errorf("OnStepDone should fire once per run step, got %d", calls)
	}
}

func TestRunOnStepStartFiresWithIndexTotal(t *testing.T) {
	now := time.Now()
	rec := recipe.Recipe{Steps: []recipe.Step{step("a", "6h", true), step("b", "6h", true)}}
	fr := &fakeRunner{result: runner.Result{Outcome: runner.OutcomeSuccess}}
	type call struct {
		id           string
		index, total int
	}
	var calls []call
	deps := Deps{Runner: fr, Now: func() time.Time { return now }, OnStepStart: func(id, _ string, index, total int) {
		calls = append(calls, call{id, index, total})
	}}
	Run(rec, state.State{}, deps, Options{})
	if len(calls) != 2 {
		t.Fatalf("OnStepStart should fire once per run step, got %d", len(calls))
	}
	if calls[0] != (call{"a", 1, 2}) || calls[1] != (call{"b", 2, 2}) {
		t.Errorf("OnStepStart index/total wrong: %+v", calls)
	}
}

func TestRunPausedSkipsCadence(t *testing.T) {
	now := time.Now()
	rec := recipe.Recipe{Steps: []recipe.Step{step("brew", "6h", true)}}
	st := state.State{"brew": {LastSuccessAt: now.Add(-7 * time.Hour)}} // 到期
	fr := &fakeRunner{result: runner.Result{Outcome: runner.OutcomeSuccess}}
	results, _ := Run(rec, st, Deps{Runner: fr, Now: func() time.Time { return now }}, Options{Paused: true})
	if len(fr.ran) != 0 {
		t.Errorf("global pause should suppress cadence run, ran=%v", fr.ran)
	}
	if results[0].Status != state.StatusSkipped || !strings.Contains(results[0].Reason, "暂停") {
		t.Errorf("paused step reason = %q", results[0].Reason)
	}
}

func TestRunPausedForceStillRuns(t *testing.T) {
	now := time.Now()
	rec := recipe.Recipe{Steps: []recipe.Step{step("brew", "6h", true)}}
	fr := &fakeRunner{result: runner.Result{Outcome: runner.OutcomeSuccess}}
	Run(rec, state.State{}, Deps{Runner: fr, Now: func() time.Time { return now }}, Options{Paused: true, Force: true})
	if len(fr.ran) != 1 {
		t.Errorf("force must override global pause, ran=%v", fr.ran)
	}
}
