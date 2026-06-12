package recipe

import (
	"os"
	"path/filepath"

	"github.com/pelletier/go-toml/v2"
)

const saveHeader = "# Horae recipe — 可由菜单栏 app 管理, 也可手编。字段说明见 docs/design.md §6。\n" +
	"# 改完用 `horae run --dry-run` 验证。\n\n"

// Save 原子写回 recipe.toml(go-toml Marshal + 头部注释)。
// 注意: 重新序列化会丢失手写的行内注释(方案甲取舍)，仅保留一段固定头部说明。
func Save(path string, rec Recipe) error {
	data, err := toml.Marshal(rec)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	out := append([]byte(saveHeader), data...)
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, out, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

// UpsertStep 按 id 插入或替换一个 step(返回新 Recipe，不改入参)。
func UpsertStep(rec Recipe, step Step) Recipe {
	steps := make([]Step, len(rec.Steps))
	copy(steps, rec.Steps)
	for i := range steps {
		if steps[i].ID == step.ID {
			steps[i] = step
			rec.Steps = steps
			return rec
		}
	}
	rec.Steps = append(steps, step)
	return rec
}

// RemoveStep 按 id 删除一个 step(返回新 Recipe + 是否删到)。
func RemoveStep(rec Recipe, id string) (Recipe, bool) {
	out := make([]Step, 0, len(rec.Steps))
	removed := false
	for _, s := range rec.Steps {
		if s.ID == id {
			removed = true
			continue
		}
		out = append(out, s)
	}
	rec.Steps = out
	return rec, removed
}
