package state

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"time"

	"github.com/pelletier/go-toml/v2"
)

type Status string

const (
	StatusSuccess Status = "success"
	StatusFailure Status = "failure"
	StatusTimeout Status = "timeout"
	StatusSkipped Status = "skipped"
	StatusNever   Status = "never"
)

type Entry struct {
	LastAttemptAt time.Time `toml:"last_attempt_at"`
	LastSuccessAt time.Time `toml:"last_success_at"`
	LastExitCode  int       `toml:"last_exit_code"`
	LastDuration  string    `toml:"last_duration"`
	LastStatus    Status    `toml:"last_status"`
}

// State 按 step id 索引。
type State map[string]Entry

func Load(path string) (State, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		return State{}, nil
	}
	if err != nil {
		return nil, err
	}
	s := State{}
	if err := toml.Unmarshal(data, &s); err != nil {
		return nil, err
	}
	return s, nil
}

// Save 原子写：先写临时文件再 rename，避免半截文件。
func Save(path string, s State) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	data, err := toml.Marshal(s)
	if err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

// IsDue：决定一个 step 本次是否该跑。
//   - 从未尝试过（attempt 与 success 均为零）→ 到期
//   - 上次失败/超时 → 距上次尝试 >= cadence 才重试（按声明频率退避，
//     避免持续失败的源在每个 launchd tick 都重跑 + 发通知刷屏）
//   - 否则（上次成功）→ 距上次成功 >= cadence 才到期
func IsDue(e Entry, cadence time.Duration, now time.Time) bool {
	if e.LastAttemptAt.IsZero() && e.LastSuccessAt.IsZero() {
		return true
	}
	if e.LastStatus == StatusFailure || e.LastStatus == StatusTimeout {
		return now.Sub(e.LastAttemptAt) >= cadence
	}
	if e.LastSuccessAt.IsZero() {
		return true
	}
	return now.Sub(e.LastSuccessAt) >= cadence
}

// NextDue：返回下次到期/重试时刻。失败/超时态按上次尝试 + cadence，
// 成功态按上次成功 + cadence；无可计算基准则 ok=false。
func NextDue(e Entry, cadence time.Duration) (time.Time, bool) {
	if e.LastStatus == StatusFailure || e.LastStatus == StatusTimeout {
		if e.LastAttemptAt.IsZero() {
			return time.Time{}, false
		}
		return e.LastAttemptAt.Add(cadence), true
	}
	if e.LastSuccessAt.IsZero() {
		return time.Time{}, false
	}
	return e.LastSuccessAt.Add(cadence), true
}
