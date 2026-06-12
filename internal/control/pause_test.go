package control

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func writeTestJSON(t *testing.T, path string, v any) {
	t.Helper()
	data, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, data, 0o600); err != nil {
		t.Fatal(err)
	}
}

func TestLoadPauseMissingFileNotPaused(t *testing.T) {
	p, err := LoadPause(filepath.Join(t.TempDir(), "nope.json"))
	if err != nil {
		t.Fatalf("missing file should not error: %v", err)
	}
	if p.Active(time.Now()) {
		t.Error("missing pause file should mean not paused")
	}
}

func TestPauseActive(t *testing.T) {
	now := time.Date(2026, 6, 12, 10, 0, 0, 0, time.UTC)
	until := now.Add(time.Hour)
	cases := []struct {
		name string
		p    Pause
		want bool
	}{
		{"not paused", Pause{Paused: false}, false},
		{"paused indefinitely", Pause{Paused: true}, true},
		{"paused until future", Pause{Paused: true, Until: &until}, true},
		{"paused until now (past boundary)", Pause{Paused: true, Until: &now}, false},
	}
	for _, c := range cases {
		if got := c.p.Active(now); got != c.want {
			t.Errorf("%s: Active=%v want %v", c.name, got, c.want)
		}
	}
}

func TestLoadPauseRoundTrip(t *testing.T) {
	path := filepath.Join(t.TempDir(), "pause.json")
	until := time.Date(2026, 6, 12, 18, 0, 0, 0, time.UTC)
	writeTestJSON(t, path, Pause{Paused: true, Until: &until})
	p, err := LoadPause(path)
	if err != nil {
		t.Fatal(err)
	}
	if !p.Paused || p.Until == nil || !p.Until.Equal(until) {
		t.Errorf("roundtrip mismatch: %+v", p)
	}
}
