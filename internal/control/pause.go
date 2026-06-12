// Package control 持有 app 写、引擎读的控制输入(全局暂停 / 每源覆盖)。
// 统一 JSON 编码(Swift Codable 友好)，stdlib encoding/json，无额外依赖。
package control

import (
	"encoding/json"
	"errors"
	"io/fs"
	"os"
	"time"
)

// Pause 是全局暂停状态(pause.json)。Until 为 nil 表示暂停到手动恢复。
type Pause struct {
	Paused bool       `json:"paused"`
	Until  *time.Time `json:"until,omitempty"`
}

// LoadPause 读取 pause.json；文件不存在视为未暂停。
func LoadPause(path string) (Pause, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		return Pause{}, nil
	}
	if err != nil {
		return Pause{}, err
	}
	var p Pause
	if err := json.Unmarshal(data, &p); err != nil {
		return Pause{}, err
	}
	return p, nil
}

// Active 判定 now 时刻是否处于暂停中。
func (p Pause) Active(now time.Time) bool {
	if !p.Paused {
		return false
	}
	if p.Until == nil {
		return true
	}
	return now.Before(*p.Until)
}
