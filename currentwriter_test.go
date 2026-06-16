package main

import (
	"encoding/json"
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

func TestCurrentWriterThrottleStaleAndReset(t *testing.T) {
	path := filepath.Join(t.TempDir(), "current.json")
	clk := time.Date(2026, 6, 16, 10, 0, 0, 0, time.UTC)
	cw := &currentWriter{
		path:   path,
		logger: slog.New(slog.NewTextHandler(io.Discard, nil)),
		now:    func() time.Time { return clk },
	}

	cw.start("s1", "L1", 1, 2)
	if c := readCurrent(t, path); !c.Running || c.Step != "s1" || c.LastLine != "" {
		t.Fatalf("start 应写 Running=s1 且无残留行, got %+v", c)
	}

	// 节流窗内的行不落盘。
	clk = clk.Add(100 * time.Millisecond)
	cw.line("s1", "a")
	if c := readCurrent(t, path); c.LastLine != "" {
		t.Errorf("节流窗内不应写出 LastLine, got %q", c.LastLine)
	}

	// 超过节流间隔则落盘最新行。
	clk = clk.Add(progressFlushInterval)
	cw.line("s1", "b")
	if c := readCurrent(t, path); c.LastLine != "b" || c.Step != "s1" {
		t.Errorf("超节流应写出最新行 b, got %+v", c)
	}

	// 跨 step 的陈旧行忽略(当前在跑 s1)。
	clk = clk.Add(progressFlushInterval)
	cw.line("s2", "x")
	if c := readCurrent(t, path); c.LastLine != "b" {
		t.Errorf("陈旧 step 的行应被忽略, got %q", c.LastLine)
	}

	// 新 step 开始清掉上一步残留的 LastLine。
	clk = clk.Add(time.Second)
	cw.start("s2", "L2", 2, 2)
	if c := readCurrent(t, path); c.Step != "s2" || c.LastLine != "" {
		t.Errorf("start 新 step 应重置, got %+v", c)
	}
}
