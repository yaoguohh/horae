package report

import "time"

// Current 是 run 期间的实时进度(current.json)。step 开始时写 Running=true，run 结束清空。
type Current struct {
	Running   bool      `json:"running"`
	Step      string    `json:"step,omitempty"`
	Label     string    `json:"label,omitempty"`
	Index     int       `json:"index,omitempty"`
	Total     int       `json:"total,omitempty"`
	StartedAt time.Time `json:"started_at,omitempty"`
}

// WriteCurrent 写实时进度。
func WriteCurrent(path string, c Current) error { return writeJSON(path, c) }

// ClearCurrent 标记当前无运行(Running=false)。
func ClearCurrent(path string) error { return writeJSON(path, Current{Running: false}) }
