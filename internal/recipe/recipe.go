package recipe

import (
	"fmt"
	"os"

	"github.com/pelletier/go-toml/v2"
)

type Recipe struct {
	Defaults Defaults `toml:"defaults"`
	Steps    []Step   `toml:"step"`
}

type Defaults struct {
	Timeout Duration `toml:"timeout"`
	Notify  string   `toml:"notify"`
}

type Step struct {
	ID      string            `toml:"id"`
	Label   string            `toml:"label,omitempty"`
	Cadence Duration          `toml:"cadence"`
	Command []string          `toml:"command,omitempty"`
	Shell   string            `toml:"shell,omitempty"`
	Timeout Duration          `toml:"timeout,omitempty"`
	Env     map[string]string `toml:"env,omitempty"`
	Enabled *bool             `toml:"enabled,omitempty"`
}

// IsEnabled：省略 enabled 时默认 true。
func (s Step) IsEnabled() bool { return s.Enabled == nil || *s.Enabled }

// DisplayName：label 缺省回落到 id。
func (s Step) DisplayName() string {
	if s.Label != "" {
		return s.Label
	}
	return s.ID
}

func Load(path string) (Recipe, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Recipe{}, fmt.Errorf("read recipe: %w", err)
	}
	var rec Recipe
	if err := toml.Unmarshal(data, &rec); err != nil {
		return Recipe{}, fmt.Errorf("parse recipe: %w", err)
	}
	if err := rec.validate(); err != nil {
		return Recipe{}, err
	}
	return rec, nil
}

func (r Recipe) validate() error {
	seen := map[string]bool{}
	for i, s := range r.Steps {
		if s.ID == "" {
			return fmt.Errorf("step[%d]: 缺少 id", i)
		}
		if seen[s.ID] {
			return fmt.Errorf("step %q: id 重复", s.ID)
		}
		seen[s.ID] = true
		if s.Cadence.Std() <= 0 {
			return fmt.Errorf("step %q: cadence 必须为正", s.ID)
		}
		hasCmd := len(s.Command) > 0
		hasShell := s.Shell != ""
		if hasCmd == hasShell {
			return fmt.Errorf("step %q: command 与 shell 必须二选一", s.ID)
		}
	}
	return nil
}
