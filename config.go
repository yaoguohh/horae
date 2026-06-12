package main

import (
	"encoding/json"
	"fmt"
	"horae/internal/paths"
	"horae/internal/recipe"
	"io"
	"os"
)

// configStep 是 app 侧的 step JSON 表示(cadence/timeout 用字符串如 "6h")。
type configStep struct {
	ID      string            `json:"id"`
	Label   string            `json:"label,omitempty"`
	Cadence string            `json:"cadence"`
	Command []string          `json:"command,omitempty"`
	Shell   string            `json:"shell,omitempty"`
	Timeout string            `json:"timeout,omitempty"`
	Env     map[string]string `json:"env,omitempty"`
	Enabled *bool             `json:"enabled,omitempty"`
}

// cmdConfig：菜单栏 app 读写 recipe 的接口(方案甲：recipe.toml 是唯一配置)。
func cmdConfig(args []string) int {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "用法: horae config <list|add|remove>")
		return 2
	}
	switch args[0] {
	case "list":
		return configList()
	case "add":
		return configAdd()
	case "remove":
		return configRemove(args[1:])
	default:
		fmt.Fprintf(os.Stderr, "未知 config 子命令: %s\n", args[0])
		return 2
	}
}

func configList() int {
	rec, err := recipe.Load(paths.Config())
	if err != nil {
		fmt.Fprintln(os.Stderr, "加载 recipe 失败:", err)
		return 1
	}
	steps := make([]configStep, 0, len(rec.Steps))
	for _, s := range rec.Steps {
		steps = append(steps, toConfigStep(s))
	}
	data, err := json.MarshalIndent(steps, "", "  ")
	if err != nil {
		fmt.Fprintln(os.Stderr, "编码失败:", err)
		return 1
	}
	fmt.Println(string(data))
	return 0
}

// configAdd 从 stdin 读一个 configStep JSON，upsert 进 recipe 并写回。
func configAdd() int {
	data, err := io.ReadAll(os.Stdin)
	if err != nil {
		fmt.Fprintln(os.Stderr, "读取 stdin 失败:", err)
		return 1
	}
	var cs configStep
	if err := json.Unmarshal(data, &cs); err != nil {
		fmt.Fprintln(os.Stderr, "解析 JSON 失败:", err)
		return 1
	}
	step, err := cs.toStep()
	if err != nil {
		fmt.Fprintln(os.Stderr, "无效 step:", err)
		return 2
	}
	rec, err := recipe.Load(paths.Config())
	if err != nil {
		fmt.Fprintln(os.Stderr, "加载 recipe 失败:", err)
		return 1
	}
	rec = recipe.UpsertStep(rec, step)
	if err := recipe.Save(paths.Config(), rec); err != nil {
		fmt.Fprintln(os.Stderr, "写 recipe 失败:", err)
		return 1
	}
	fmt.Println("已添加/更新:", step.ID)
	return 0
}

func configRemove(args []string) int {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "用法: horae config remove <id>")
		return 2
	}
	rec, err := recipe.Load(paths.Config())
	if err != nil {
		fmt.Fprintln(os.Stderr, "加载 recipe 失败:", err)
		return 1
	}
	rec, ok := recipe.RemoveStep(rec, args[0])
	if !ok {
		fmt.Fprintf(os.Stderr, "未找到 step: %s\n", args[0])
		return 2
	}
	if err := recipe.Save(paths.Config(), rec); err != nil {
		fmt.Fprintln(os.Stderr, "写 recipe 失败:", err)
		return 1
	}
	fmt.Println("已删除:", args[0])
	return 0
}

func toConfigStep(s recipe.Step) configStep {
	cs := configStep{
		ID: s.ID, Label: s.Label, Cadence: durStr(s.Cadence),
		Command: s.Command, Shell: s.Shell, Env: s.Env, Enabled: s.Enabled,
	}
	if s.Timeout.Std() > 0 {
		cs.Timeout = durStr(s.Timeout)
	}
	return cs
}

func (cs configStep) toStep() (recipe.Step, error) {
	if cs.ID == "" {
		return recipe.Step{}, fmt.Errorf("缺少 id")
	}
	cad, err := recipe.ParseDuration(cs.Cadence)
	if err != nil {
		return recipe.Step{}, fmt.Errorf("cadence: %w", err)
	}
	hasCmd := len(cs.Command) > 0
	hasShell := cs.Shell != ""
	if hasCmd == hasShell {
		return recipe.Step{}, fmt.Errorf("command 与 shell 必须二选一")
	}
	step := recipe.Step{
		ID: cs.ID, Label: cs.Label, Cadence: recipe.Duration(cad),
		Command: cs.Command, Shell: cs.Shell, Env: cs.Env, Enabled: cs.Enabled,
	}
	if cs.Timeout != "" {
		to, err := recipe.ParseDuration(cs.Timeout)
		if err != nil {
			return recipe.Step{}, fmt.Errorf("timeout: %w", err)
		}
		step.Timeout = recipe.Duration(to)
	}
	return step, nil
}

func durStr(d recipe.Duration) string {
	b, _ := d.MarshalText()
	return string(b)
}
