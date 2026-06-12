package report

import (
	"horae/internal/control"
	"horae/internal/recipe"
	"horae/internal/state"
	"testing"
	"time"
)

func dur6h() recipe.Duration { d, _ := recipe.ParseDuration("6h"); return recipe.Duration(d) }
func ptrFalse() *bool        { b := false; return &b }

func TestBuildStatusReflectsStateAndPause(t *testing.T) {
	now := time.Date(2026, 6, 12, 12, 0, 0, 0, time.UTC)
	rec := recipe.Recipe{Steps: []recipe.Step{
		{ID: "brew", Label: "Homebrew", Cadence: dur6h()},
		{ID: "pipx", Cadence: dur6h(), Enabled: ptrFalse()},
	}}
	st := state.State{"brew": {LastSuccessAt: now.Add(-time.Hour), LastStatus: state.StatusSuccess, LastDuration: "41s"}}
	until := now.Add(time.Hour)
	view := BuildStatus(rec, st, control.Pause{Paused: true, Until: &until}, now)

	if !view.Paused || view.PausedUntil == nil {
		t.Errorf("view should reflect pause: %+v", view)
	}
	if len(view.Sources) != 2 {
		t.Fatalf("want 2 sources, got %d", len(view.Sources))
	}
	brew := view.Sources[0]
	if brew.Label != "Homebrew" || brew.Status != "success" || brew.LastSuccessAt == nil {
		t.Errorf("brew source = %+v", brew)
	}
	if brew.NextDueAt == nil || !brew.Enabled {
		t.Errorf("brew should have next due + enabled: %+v", brew)
	}
	pipx := view.Sources[1]
	if pipx.Enabled {
		t.Error("pipx disabled in recipe should be Enabled=false")
	}
	if pipx.Status != "never" {
		t.Errorf("pipx never ran should be status never, got %q", pipx.Status)
	}
	if pipx.Due {
		t.Error("disabled source should not be marked due")
	}
}
