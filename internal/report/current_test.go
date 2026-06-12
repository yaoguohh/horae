package report

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func readJSON(t *testing.T, path string, v any) {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(data, v); err != nil {
		t.Fatal(err)
	}
}

func TestWriteAndClearCurrent(t *testing.T) {
	path := filepath.Join(t.TempDir(), "current.json")
	now := time.Date(2026, 6, 12, 10, 0, 0, 0, time.UTC)
	c := Current{Running: true, Step: "claude", Label: "Claude Code", Index: 2, Total: 5, StartedAt: now}
	if err := WriteCurrent(path, c); err != nil {
		t.Fatal(err)
	}
	var got Current
	readJSON(t, path, &got)
	if !got.Running || got.Step != "claude" || got.Total != 5 {
		t.Errorf("current mismatch: %+v", got)
	}

	if err := ClearCurrent(path); err != nil {
		t.Fatal(err)
	}
	readJSON(t, path, &got)
	if got.Running {
		t.Error("ClearCurrent should set running=false")
	}

	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Errorf("current.json perm = %v, want 0600", info.Mode().Perm())
	}
}
