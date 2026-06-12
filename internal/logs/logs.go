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
// 文件名按本地时区生成(paths.Log)，故解析与 cutoff 都对齐到 now 所在时区的当天 00:00，
// 否则本地/UTC 混比会在非 UTC 时区造成保留边界 off-by-one。
func stale(names []string, now time.Time, keepDays int) []string {
	y, m, d := now.Date()
	cutoff := time.Date(y, m, d, 0, 0, 0, 0, now.Location()).AddDate(0, 0, -keepDays)
	var out []string
	for _, n := range names {
		date, ok := logDate(n, now.Location())
		if ok && date.Before(cutoff) {
			out = append(out, n)
		}
	}
	return out
}

// logDate 从 run-YYYYMMDD.log 解析日期(按 loc 取当天 00:00)；非此格式返回 ok=false。
func logDate(name string, loc *time.Location) (time.Time, bool) {
	if !strings.HasPrefix(name, "run-") || !strings.HasSuffix(name, ".log") {
		return time.Time{}, false
	}
	ds := strings.TrimSuffix(strings.TrimPrefix(name, "run-"), ".log")
	t, err := time.ParseInLocation("20060102", ds, loc)
	if err != nil {
		return time.Time{}, false
	}
	return t, true
}
