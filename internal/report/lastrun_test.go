package report

import (
	"horae/internal/orchestrator"
	"horae/internal/recipe"
	"horae/internal/state"
	"path/filepath"
	"testing"
	"time"
)

func TestBuildLastRunCountsAndExcludesSkipped(t *testing.T) {
	now := time.Date(2026, 6, 12, 10, 0, 0, 0, time.UTC)
	results := []orchestrator.StepResult{
		{Step: recipe.Step{ID: "brew", Label: "Homebrew"}, Status: state.StatusSuccess, Duration: 41 * time.Second},
		{Step: recipe.Step{ID: "rustup"}, Status: state.StatusFailure, ExitCode: 1, StderrTail: "boom"},
		{Step: recipe.Step{ID: "pipx"}, Status: state.StatusSkipped, Reason: "未到期"},
	}
	lr := Build(results, "on_change", now)
	if lr.Summary.Ran != 2 || lr.Summary.OK != 1 || lr.Summary.Failed != 1 || lr.Summary.Skipped != 1 {
		t.Errorf("summary = %+v", lr.Summary)
	}
	if !lr.ShouldNotify {
		t.Error("on_change with a run should notify")
	}
	if len(lr.Steps) != 2 {
		t.Fatalf("skipped step must not appear in steps, got %d", len(lr.Steps))
	}
	if lr.Steps[0].Label != "Homebrew" || lr.Steps[0].Duration != "41s" {
		t.Errorf("step report = %+v", lr.Steps[0])
	}
	if lr.Steps[0].Changes == nil {
		t.Error("changes should be non-nil empty slice in phase 1")
	}
	if lr.Steps[1].OutputTail != "boom" {
		t.Errorf("failure output tail = %q", lr.Steps[1].OutputTail)
	}
}

func TestWriteLastRunRoundTrip(t *testing.T) {
	path := filepath.Join(t.TempDir(), "last-run.json")
	lr := Build([]orchestrator.StepResult{
		{Step: recipe.Step{ID: "brew"}, Status: state.StatusSuccess},
	}, "always", time.Now())
	if err := WriteLastRun(path, lr); err != nil {
		t.Fatal(err)
	}
	var got LastRun
	readJSON(t, path, &got)
	if got.NotifyPolicy != "always" || !got.ShouldNotify {
		t.Errorf("roundtrip mismatch: %+v", got)
	}
}
