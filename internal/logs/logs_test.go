package logs

import (
	"testing"
	"time"
)

func TestStaleLogs(t *testing.T) {
	now := time.Date(2026, 6, 12, 10, 0, 0, 0, time.UTC)
	names := []string{
		"run-20260612.log", // 今天，保留
		"run-20260601.log", // 11 天前，保留
		"run-20260528.log", // 15 天前，删
		"run-20260501.log", // 更久，删
		"run-bad.log",      // 非日期，忽略
		"other.txt",        // 忽略
		"launchd.out.log",  // 非 run-，忽略
	}
	got := stale(names, now, 14)
	want := map[string]bool{"run-20260528.log": true, "run-20260501.log": true}
	if len(got) != len(want) {
		t.Fatalf("stale = %v, want %v", got, want)
	}
	for _, s := range got {
		if !want[s] {
			t.Errorf("unexpected stale: %s", s)
		}
	}
}

func TestStaleBoundary(t *testing.T) {
	now := time.Date(2026, 6, 12, 0, 0, 0, 0, time.UTC)
	// cutoff = now - 14d = 2026-05-29 00:00；当天保留，前一天删。
	if got := stale([]string{"run-20260529.log"}, now, 14); len(got) != 0 {
		t.Errorf("边界当天应保留, got %v", got)
	}
	if got := stale([]string{"run-20260528.log"}, now, 14); len(got) != 1 {
		t.Errorf("边界前一天应删, got %v", got)
	}
}

// TestStaleBoundaryNonUTC 守护非 UTC 时区下的边界：文件名按本地日期生成，
// 而旧实现把日期解析成 UTC 午夜再与本地 cutoff 混比，会在负偏移时区误删 cutoff 当天的日志。
func TestStaleBoundaryNonUTC(t *testing.T) {
	loc := time.FixedZone("UTC-7", -7*3600)
	now := time.Date(2026, 6, 12, 23, 0, 0, 0, loc)
	// cutoff 日期 = now - 14d = 2026-05-29；按本地日历日，当天保留，前一天删。
	if got := stale([]string{"run-20260529.log"}, now, 14); len(got) != 0 {
		t.Errorf("UTC-7 边界当天应保留, got %v", got)
	}
	if got := stale([]string{"run-20260528.log"}, now, 14); len(got) != 1 {
		t.Errorf("UTC-7 边界前一天应删, got %v", got)
	}
}
