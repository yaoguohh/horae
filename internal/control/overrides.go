package control

import (
	"encoding/json"
	"errors"
	"horae/internal/recipe"
	"io/fs"
	"os"
)

// Override 是单个源的 app 侧覆盖(目前仅 enabled)。
type Override struct {
	Enabled *bool `json:"enabled,omitempty"`
}

// Overrides 按 step id 索引(overrides.json)。
type Overrides map[string]Override

// LoadOverrides 读取 overrides.json；文件不存在视为无覆盖。
func LoadOverrides(path string) (Overrides, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		return Overrides{}, nil
	}
	if err != nil {
		return Overrides{}, err
	}
	o := Overrides{}
	if err := json.Unmarshal(data, &o); err != nil {
		return Overrides{}, err
	}
	return o, nil
}

// Apply 把覆盖叠加到 steps，返回新 slice(不改入参)。目前仅覆盖 enabled。
func (o Overrides) Apply(steps []recipe.Step) []recipe.Step {
	if len(o) == 0 {
		return steps
	}
	out := make([]recipe.Step, len(steps))
	copy(out, steps)
	for i := range out {
		if ov, ok := o[out[i].ID]; ok && ov.Enabled != nil {
			out[i].Enabled = ov.Enabled
		}
	}
	return out
}
