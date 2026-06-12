package control

import (
	"horae/internal/recipe"
	"path/filepath"
	"testing"
)

func TestLoadOverridesMissingFileEmpty(t *testing.T) {
	o, err := LoadOverrides(filepath.Join(t.TempDir(), "nope.json"))
	if err != nil {
		t.Fatalf("missing file should not error: %v", err)
	}
	if len(o) != 0 {
		t.Errorf("missing overrides should be empty, got %v", o)
	}
}

func TestOverridesApplyDisablesStep(t *testing.T) {
	on := true
	steps := []recipe.Step{
		{ID: "brew", Enabled: &on},
		{ID: "claude", Enabled: &on},
	}
	off := false
	out := Overrides{"claude": {Enabled: &off}}.Apply(steps)
	if !out[0].IsEnabled() {
		t.Error("brew should stay enabled")
	}
	if out[1].IsEnabled() {
		t.Error("claude should be disabled by override")
	}
	if !steps[1].IsEnabled() {
		t.Error("Apply must not mutate input slice")
	}
}

func TestOverridesApplyEmptyPassThrough(t *testing.T) {
	steps := []recipe.Step{{ID: "brew"}}
	out := Overrides{}.Apply(steps)
	if len(out) != 1 || out[0].ID != "brew" {
		t.Errorf("empty overrides should pass through: %v", out)
	}
}

func TestLoadOverridesRoundTrip(t *testing.T) {
	path := filepath.Join(t.TempDir(), "overrides.json")
	off := false
	writeTestJSON(t, path, Overrides{"pipx": {Enabled: &off}})
	o, err := LoadOverrides(path)
	if err != nil {
		t.Fatal(err)
	}
	ov, ok := o["pipx"]
	if !ok || ov.Enabled == nil || *ov.Enabled {
		t.Errorf("roundtrip mismatch: %+v", o)
	}
}
