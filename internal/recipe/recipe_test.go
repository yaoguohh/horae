package recipe

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

const sample = `
[defaults]
timeout = "10m"
notify  = "on_change"

[[step]]
id      = "brew"
label   = "Homebrew"
cadence = "6h"
command = ["/opt/homebrew/bin/brew", "upgrade"]

[[step]]
id      = "npm"
cadence = "8h"
shell   = "npm update -g"
enabled = false
`

func TestLoad(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "recipes.toml")
	if err := os.WriteFile(path, []byte(sample), 0o644); err != nil {
		t.Fatal(err)
	}
	rec, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	if rec.Defaults.Timeout.Std() != 10*time.Minute {
		t.Errorf("defaults.timeout = %v", rec.Defaults.Timeout.Std())
	}
	if rec.Defaults.Notify != "on_change" {
		t.Errorf("notify = %q", rec.Defaults.Notify)
	}
	if len(rec.Steps) != 2 {
		t.Fatalf("steps = %d, want 2", len(rec.Steps))
	}
	brew := rec.Steps[0]
	if brew.ID != "brew" || brew.Label != "Homebrew" || brew.Cadence.Std() != 6*time.Hour {
		t.Errorf("brew step parsed wrong: %+v", brew)
	}
	if !brew.IsEnabled() {
		t.Error("brew should be enabled by default")
	}
	if rec.Steps[1].IsEnabled() {
		t.Error("npm should be disabled")
	}
	if rec.Steps[1].DisplayName() != "npm" {
		t.Errorf("npm DisplayName = %q, want npm", rec.Steps[1].DisplayName())
	}
}

func TestValidate(t *testing.T) {
	bad := []string{
		`[[step]]
cadence = "6h"
command = ["true"]`, // 缺 id
		`[[step]]
id = "x"
command = ["true"]`, // 缺 cadence
		`[[step]]
id = "x"
cadence = "6h"`, // command 与 shell 都缺
		`[[step]]
id = "x"
cadence = "6h"
command = ["true"]
shell = "true"`, // command 与 shell 同时有
	}
	dir := t.TempDir()
	for i, src := range bad {
		path := filepath.Join(dir, "bad.toml")
		os.WriteFile(path, []byte(src), 0o644)
		if _, err := Load(path); err == nil {
			t.Errorf("case %d: expected validation error, got nil", i)
		}
	}
}
