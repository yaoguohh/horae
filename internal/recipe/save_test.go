package recipe

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func dur(s string) Duration { d, _ := ParseDuration(s); return Duration(d) }

func TestSaveRoundTrip(t *testing.T) {
	path := filepath.Join(t.TempDir(), "recipes.toml")
	on := true
	rec := Recipe{
		Defaults: Defaults{Timeout: dur("15m"), Notify: "on_change"},
		Steps: []Step{
			{ID: "brew", Label: "Homebrew", Cadence: dur("3h"), Shell: "brew upgrade", Timeout: dur("30m")},
			{ID: "uv", Label: "uv tools", Cadence: dur("1d"), Command: []string{"uv", "tool", "upgrade", "--all"}, Enabled: &on},
		},
	}
	if err := Save(path, rec); err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(path)
	s := string(data)
	// cadence 必须短格式化，而非 time.Duration 的纳秒整数。
	if strings.Contains(s, "10800000000000") {
		t.Errorf("cadence 输出成纳秒整数:\n%s", s)
	}
	if !strings.Contains(s, "3h") {
		t.Errorf("cadence 未短格式化:\n%s", s)
	}
	// 回读应等价。
	got, err := Load(path)
	if err != nil {
		t.Fatalf("回读失败: %v", err)
	}
	if len(got.Steps) != 2 || got.Steps[0].ID != "brew" || got.Steps[0].Cadence.Std() != dur("3h").Std() {
		t.Errorf("round-trip mismatch: %+v", got.Steps)
	}
	if !got.Steps[1].IsEnabled() || len(got.Steps[1].Command) != 4 {
		t.Errorf("command/enabled round-trip mismatch: %+v", got.Steps[1])
	}
}

// TestSaveRejectsInvalid 守护写入闸门与读取(Load)共享同一校验：
// 非正 cadence 不得被持久化，否则下次 Load 会因 "cadence 必须为正" 报错，
// 陷入产品自己写坏自己、须手改文件才能恢复的死局。
func TestSaveRejectsInvalid(t *testing.T) {
	path := filepath.Join(t.TempDir(), "recipes.toml")
	for _, bad := range []string{"0s", "-5m"} {
		rec := Recipe{Steps: []Step{{ID: "x", Cadence: dur(bad), Shell: "echo hi"}}}
		if err := Save(path, rec); err == nil {
			t.Errorf("Save 应拒绝 cadence=%s", bad)
		}
	}
}

func TestUpsertAndRemove(t *testing.T) {
	rec := Recipe{Steps: []Step{{ID: "brew", Cadence: dur("3h")}}}
	rec = UpsertStep(rec, Step{ID: "uv", Cadence: dur("1d")})
	if len(rec.Steps) != 2 {
		t.Fatalf("upsert 新增失败: %d", len(rec.Steps))
	}
	rec = UpsertStep(rec, Step{ID: "brew", Cadence: dur("6h"), Label: "新"})
	if len(rec.Steps) != 2 || rec.Steps[0].Cadence.Std() != dur("6h").Std() || rec.Steps[0].Label != "新" {
		t.Errorf("upsert 替换失败: %+v", rec.Steps[0])
	}
	rec, ok := RemoveStep(rec, "uv")
	if !ok || len(rec.Steps) != 1 {
		t.Errorf("remove 失败: ok=%v len=%d", ok, len(rec.Steps))
	}
	if _, ok := RemoveStep(rec, "nope"); ok {
		t.Error("remove 不存在的应返回 false")
	}
}
