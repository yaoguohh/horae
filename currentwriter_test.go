package main

import (
	"encoding/json"
	"fmt"
	"horae/internal/report"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func readCurrent(t *testing.T, path string) report.Current {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read current.json: %v", err)
	}
	var c report.Current
	if err := json.Unmarshal(data, &c); err != nil {
		t.Fatalf("decode current.json: %v", err)
	}
	return c
}

func lastLine(c report.Current) string {
	if len(c.LastLines) == 0 {
		return ""
	}
	return c.LastLines[len(c.LastLines)-1]
}

func TestCurrentWriterThrottleStaleAndReset(t *testing.T) {
	path := filepath.Join(t.TempDir(), "current.json")
	clk := time.Date(2026, 6, 16, 10, 0, 0, 0, time.UTC)
	cw := &currentWriter{
		path:   path,
		logger: slog.New(slog.NewTextHandler(io.Discard, nil)),
		now:    func() time.Time { return clk },
	}

	cw.start("s1", "L1", 1, 2)
	if c := readCurrent(t, path); !c.Running || c.Step != "s1" || len(c.LastLines) != 0 {
		t.Fatalf("start 应写 Running=s1 且无残留行, got %+v", c)
	}

	// 节流窗内的行不落盘。
	clk = clk.Add(100 * time.Millisecond)
	cw.line("s1", "a")
	if c := readCurrent(t, path); len(c.LastLines) != 0 {
		t.Errorf("节流窗内不应写出, got %v", c.LastLines)
	}

	// 超过节流间隔则落盘环(节流窗内累积的行也一并写出)。
	clk = clk.Add(progressFlushInterval)
	cw.line("s1", "b")
	if c := readCurrent(t, path); lastLine(c) != "b" || c.Step != "s1" {
		t.Errorf("超节流应写出最新行 b, got %+v", c)
	}

	// 跨 step 的陈旧行忽略(当前在跑 s1)。
	clk = clk.Add(progressFlushInterval)
	cw.line("s2", "x")
	if c := readCurrent(t, path); lastLine(c) != "b" {
		t.Errorf("陈旧 step 的行应被忽略, got %v", c.LastLines)
	}

	// 新 step 开始清掉上一步残留的环。
	clk = clk.Add(time.Second)
	cw.start("s2", "L2", 2, 2)
	if c := readCurrent(t, path); c.Step != "s2" || len(c.LastLines) != 0 {
		t.Errorf("start 新 step 应重置, got %+v", c)
	}
}

// 有界环：超过 maxProgressLines 行后只保留最近 N 行，最旧的丢弃。
func TestCurrentWriterRingCap(t *testing.T) {
	path := filepath.Join(t.TempDir(), "current.json")
	clk := time.Date(2026, 6, 16, 10, 0, 0, 0, time.UTC)
	cw := &currentWriter{
		path:   path,
		logger: slog.New(slog.NewTextHandler(io.Discard, nil)),
		now:    func() time.Time { return clk },
	}
	cw.start("s", "L", 1, 1)
	total := maxProgressLines + 5
	for i := 1; i <= total; i++ {
		clk = clk.Add(progressFlushInterval) // 每行都越过节流, 确保落盘
		cw.line("s", fmt.Sprintf("l%d", i))
	}
	c := readCurrent(t, path)
	if len(c.LastLines) != maxProgressLines {
		t.Fatalf("环应裁到 %d 行, got %d (%v)", maxProgressLines, len(c.LastLines), c.LastLines)
	}
	if c.LastLines[0] != "l6" || lastLine(c) != fmt.Sprintf("l%d", total) {
		t.Errorf("应保留最近 %d 行(l6..l%d), got %v", maxProgressLines, total, c.LastLines)
	}
}
