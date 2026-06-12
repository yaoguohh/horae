package orchestrator

import (
	"horae/internal/recipe"
	"horae/internal/state"
	"strings"
	"testing"
	"time"
)

func TestShouldNotify(t *testing.T) {
	ran := []StepResult{{Status: state.StatusSuccess}}
	failed := []StepResult{{Status: state.StatusFailure}}
	allSkipped := []StepResult{{Status: state.StatusSkipped}}

	if ShouldNotify("never", ran) {
		t.Error("never should never notify")
	}
	if !ShouldNotify("always", allSkipped) {
		t.Error("always should notify even when all skipped")
	}
	if ShouldNotify("on_change", allSkipped) {
		t.Error("on_change should stay silent when all skipped")
	}
	if !ShouldNotify("on_change", ran) {
		t.Error("on_change should notify when a step ran")
	}
	if ShouldNotify("on_failure", ran) {
		t.Error("on_failure should not notify on pure success")
	}
	if !ShouldNotify("on_failure", failed) {
		t.Error("on_failure should notify on failure")
	}
}

func TestRenderStatus(t *testing.T) {
	now := time.Date(2026, 5, 29, 12, 0, 0, 0, time.UTC)
	rec := recipe.Recipe{Steps: []recipe.Step{
		{ID: "brew", Label: "Homebrew", Cadence: dur6h()},
		{ID: "pipx", Cadence: dur6h(), Enabled: ptrFalse()},
	}}
	st := state.State{"brew": {LastSuccessAt: now.Add(-1 * time.Hour), LastStatus: state.StatusSuccess, LastDuration: "41s"}}
	out := RenderStatus(rec, st, now)
	if !strings.Contains(out, "Homebrew") || !strings.Contains(out, "未启用") {
		t.Errorf("status output:\n%s", out)
	}
}

func TestDisplayWidthAndPad(t *testing.T) {
	if displayWidth("abc") != 3 {
		t.Errorf("ascii width = %d, want 3", displayWidth("abc"))
	}
	if displayWidth("回显测试") != 8 {
		t.Errorf("CJK width = %d, want 8", displayWidth("回显测试"))
	}
	// "回显测试"(宽 8) 补到 16 → 末尾 8 个空格
	if got := pad("回显测试", 16); got != "回显测试"+strings.Repeat(" ", 8) {
		t.Errorf("pad CJK = %q", got)
	}
	// 超出宽度原样返回
	if got := pad("abcdef", 4); got != "abcdef" {
		t.Errorf("pad overflow = %q", got)
	}
}

func TestRenderStatusFailedNeverSucceededShowsDue(t *testing.T) {
	now := time.Date(2026, 5, 29, 12, 0, 0, 0, time.UTC)
	rec := recipe.Recipe{Steps: []recipe.Step{{ID: "brew", Label: "Homebrew", Cadence: dur6h()}}}
	// 只失败过、从未成功，且上次尝试已超 cadence → 应显示“到期”而非“—”
	st := state.State{"brew": {LastAttemptAt: now.Add(-7 * time.Hour), LastStatus: state.StatusFailure, LastDuration: "3s"}}
	out := RenderStatus(rec, st, now)
	if !strings.Contains(out, "到期") {
		t.Errorf("overdue failed step should show 到期, got:\n%s", out)
	}
	if !strings.Contains(out, "failure") {
		t.Errorf("should show failure status:\n%s", out)
	}
}

func dur6h() recipe.Duration { d, _ := recipe.ParseDuration("6h"); return recipe.Duration(d) }
func ptrFalse() *bool        { b := false; return &b }
