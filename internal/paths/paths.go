package paths

import (
	"os"
	"path/filepath"
	"time"
)

func home() string {
	h, _ := os.UserHomeDir()
	return h
}

func base(envVar, fallback string) string {
	if v := os.Getenv(envVar); v != "" {
		return v
	}
	return filepath.Join(home(), fallback)
}

func Config() string {
	return filepath.Join(base("XDG_CONFIG_HOME", ".config"), "horae", "recipes.toml")
}

// stateDir 是所有跨运行 / 进程间文件的根(state.toml + 锁 + app 契约文件)。
func stateDir() string {
	return filepath.Join(base("XDG_STATE_HOME", ".local/state"), "horae")
}

func State() string { return filepath.Join(stateDir(), "state.toml") }

func Lock() string { return filepath.Join(stateDir(), "horae.lock") }

// Current 是引擎写、菜单栏 app 读的实时进度(running step)。
func Current() string { return filepath.Join(stateDir(), "current.json") }

// LastRun 是引擎写、app 读的最近一次 run 结果 + 通知决策。
func LastRun() string { return filepath.Join(stateDir(), "last-run.json") }

// Pause 是 app 写、引擎读的全局暂停状态。
func Pause() string { return filepath.Join(stateDir(), "pause.json") }

// Overrides 是 app 写、引擎读的每源覆盖(enabled)。统一 JSON 便于 Swift Codable。
func Overrides() string { return filepath.Join(stateDir(), "overrides.json") }

// LogDir：日志目录 ~/Library/Logs/horae。
func LogDir() string {
	return filepath.Join(home(), "Library", "Logs", "horae")
}

// Log：macOS 习惯放 ~/Library/Logs/horae/run-YYYYMMDD.log。
func Log() string {
	day := time.Now().Format("20060102")
	return filepath.Join(LogDir(), "run-"+day+".log")
}
