// Package logs 负责运行日志的清理(轮转)：只保留近 keepDays 天的 run-YYYYMMDD.log。
package logs

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Prune 删除 dir 下早于 now-keepDays 天的 run 日志。dir 不存在不算错。
func Prune(dir string, keepDays int, now time.Time) error {
	entries, err := os.ReadDir(dir)
	if errors.Is(err, fs.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	names := make([]string, 0, len(entries))
	for _, e := range entries {
		if !e.IsDir() {
			names = append(names, e.Name())
		}
	}
	var firstErr error
	for _, n := range stale(names, now, keepDays) {
		if err := os.Remove(filepath.Join(dir, n)); err != nil && firstErr == nil {
			firstErr = err
		}
	}
	return firstErr
}

// stale 返回 names 中早于 now-keepDays 天的 run-YYYYMMDD.log 文件名(纯函数，可测)。
func stale(names []string, now time.Time, keepDays int) []string {
	cutoff := now.AddDate(0, 0, -keepDays)
	var out []string
	for _, n := range names {
		d, ok := logDate(n)
		if ok && d.Before(cutoff) {
			out = append(out, n)
		}
	}
	return out
}

// logDate 从 run-YYYYMMDD.log 解析日期；非此格式返回 ok=false。
func logDate(name string) (time.Time, bool) {
	if !strings.HasPrefix(name, "run-") || !strings.HasSuffix(name, ".log") {
		return time.Time{}, false
	}
	ds := strings.TrimSuffix(strings.TrimPrefix(name, "run-"), ".log")
	t, err := time.Parse("20060102", ds)
	if err != nil {
		return time.Time{}, false
	}
	return t, true
}
