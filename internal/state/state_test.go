package state

import (
	"path/filepath"
	"testing"
	"time"
)

func TestLoadMissingReturnsEmpty(t *testing.T) {
	s, err := Load(filepath.Join(t.TempDir(), "nope.toml"))
	if err != nil {
		t.Fatal(err)
	}
	if len(s) != 0 {
		t.Errorf("expected empty state, got %d entries", len(s))
	}
}

func TestSaveLoadRoundTrip(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state.toml")
	now := time.Date(2026, 5, 29, 7, 22, 0, 0, time.UTC)
	in := State{"brew": Entry{
		LastAttemptAt: now,
		LastSuccessAt: now,
		LastExitCode:  0,
		LastDuration:  "41s",
		LastStatus:    StatusSuccess,
	}}
	if err := Save(path, in); err != nil {
		t.Fatal(err)
	}
	out, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	e := out["brew"]
	if e.LastStatus != StatusSuccess || e.LastDuration != "41s" || !e.LastSuccessAt.Equal(now) {
		t.Errorf("round trip mismatch: %+v", e)
	}
}

func TestIsDue(t *testing.T) {
	now := time.Date(2026, 5, 29, 12, 0, 0, 0, time.UTC)
	if !IsDue(Entry{}, 6*time.Hour, now) {
		t.Error("never-succeeded entry should be due")
	}
	e := Entry{LastSuccessAt: now.Add(-5 * time.Hour)}
	if IsDue(e, 6*time.Hour, now) {
		t.Error("5h ago with 6h cadence should NOT be due")
	}
	e2 := Entry{LastSuccessAt: now.Add(-7 * time.Hour)}
	if !IsDue(e2, 6*time.Hour, now) {
		t.Error("7h ago with 6h cadence should be due")
	}
}

func TestNextDue(t *testing.T) {
	now := time.Date(2026, 5, 29, 12, 0, 0, 0, time.UTC)
	if _, ok := NextDue(Entry{}, 6*time.Hour); ok {
		t.Error("never-succeeded entry has no NextDue")
	}
	e := Entry{LastSuccessAt: now}
	nd, ok := NextDue(e, 6*time.Hour)
	if !ok || !nd.Equal(now.Add(6*time.Hour)) {
		t.Errorf("NextDue = %v ok=%v", nd, ok)
	}
}

func TestIsDueFailureBackoff(t *testing.T) {
	now := time.Date(2026, 5, 29, 12, 0, 0, 0, time.UTC)
	// 上次失败、距今 1h（< cadence 6h）→ 退避，不重试（关键：不再每 tick 重跑）
	recent := Entry{LastAttemptAt: now.Add(-1 * time.Hour), LastStatus: StatusFailure}
	if IsDue(recent, 6*time.Hour, now) {
		t.Error("recently-failed step within cadence should NOT retry every tick")
	}
	// 上次失败、距今 7h（>= cadence 6h）→ 到期重试
	old := Entry{LastAttemptAt: now.Add(-7 * time.Hour), LastStatus: StatusFailure}
	if !IsDue(old, 6*time.Hour, now) {
		t.Error("failed step past cadence should retry")
	}
	// 超时态同退避
	timedOut := Entry{LastAttemptAt: now.Add(-1 * time.Hour), LastStatus: StatusTimeout}
	if IsDue(timedOut, 6*time.Hour, now) {
		t.Error("recently-timed-out step within cadence should NOT retry every tick")
	}
}

func TestNextDueForFailure(t *testing.T) {
	now := time.Date(2026, 5, 29, 12, 0, 0, 0, time.UTC)
	// 失败态：下次重试 = 上次尝试 + cadence（即使从未成功也能算出下次）
	e := Entry{LastAttemptAt: now, LastStatus: StatusFailure}
	nd, ok := NextDue(e, 6*time.Hour)
	if !ok || !nd.Equal(now.Add(6*time.Hour)) {
		t.Errorf("failed NextDue = %v ok=%v, want %v", nd, ok, now.Add(6*time.Hour))
	}
}
