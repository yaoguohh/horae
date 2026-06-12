package orchestrator

import (
	"fmt"
	"horae/internal/recipe"
	"horae/internal/state"
	"strings"
	"time"
)

// ShouldNotify 按策略判定是否发通知。结果写入 last-run.json，由菜单栏 app 据此发原生通知。
func ShouldNotify(policy string, results []StepResult) bool {
	var ranAny, failedAny bool
	for _, r := range results {
		switch r.Status {
		case state.StatusSuccess:
			ranAny = true
		case state.StatusFailure, state.StatusTimeout:
			ranAny, failedAny = true, true
		}
	}
	switch policy {
	case "never":
		return false
	case "always":
		return true
	case "on_failure":
		return failedAny
	default: // on_change（默认）
		return ranAny
	}
}

// RenderStatus 渲染 status 子命令的状态表。
func RenderStatus(rec recipe.Recipe, st state.State, now time.Time) string {
	var b strings.Builder
	writeRow(&b, "源", "上次成功", "上次结果", "耗时", "距下次到期")
	for _, step := range rec.Steps {
		e := st[step.ID]
		success, dueIn := "—", "—"
		status, elapsed := "—", "—"
		switch {
		case !step.IsEnabled():
			status = "未启用"
		case e.LastSuccessAt.IsZero() && e.LastStatus == "":
			status = "从未跑"
			dueIn = "到期"
		default:
			if !e.LastSuccessAt.IsZero() {
				success = e.LastSuccessAt.Local().Format("01-02 15:04")
			}
			if e.LastStatus != "" {
				status = string(e.LastStatus)
			}
			if e.LastDuration != "" {
				elapsed = e.LastDuration
			}
			// 距下次到期/重试：成功态按上次成功、失败态按上次尝试统一计算（见 state.NextDue）。
			// 算不出基准但已判到期（如只失败过、从未成功）则显式标“到期”，不留空掩盖 overdue。
			if nd, ok := state.NextDue(e, step.Cadence.Std()); ok {
				if rem := nd.Sub(now); rem <= 0 {
					dueIn = "到期"
				} else {
					dueIn = humanShort(rem)
				}
			} else if state.IsDue(e, step.Cadence.Std(), now) {
				dueIn = "到期"
			}
		}
		writeRow(&b, step.DisplayName(), success, status, elapsed, dueIn)
	}
	return b.String()
}

// writeRow 写一行状态表，列按显示宽度（CJK 双宽）左对齐补齐，末列不补。
func writeRow(b *strings.Builder, name, success, status, elapsed, dueIn string) {
	b.WriteString(pad(name, 16))
	b.WriteByte(' ')
	b.WriteString(pad(success, 18))
	b.WriteByte(' ')
	b.WriteString(pad(status, 10))
	b.WriteByte(' ')
	b.WriteString(pad(elapsed, 8))
	b.WriteByte(' ')
	b.WriteString(dueIn)
	b.WriteByte('\n')
}

// pad 按显示宽度右侧补空格到 width（不足才补；超出原样返回）。
func pad(s string, width int) string {
	dw := displayWidth(s)
	if dw >= width {
		return s
	}
	return s + strings.Repeat(" ", width-dw)
}

// displayWidth 计算字符串终端显示宽度，East Asian Wide/Fullwidth 记 2 列。
func displayWidth(s string) int {
	w := 0
	for _, r := range s {
		if isWide(r) {
			w += 2
		} else {
			w++
		}
	}
	return w
}

func isWide(r rune) bool {
	switch {
	case r >= 0x1100 && r <= 0x115F, // Hangul Jamo
		r >= 0x2E80 && r <= 0xA4CF,   // CJK 部首/康熙/CJK 符号/假名/CJK 统一表意 等
		r >= 0xAC00 && r <= 0xD7A3,   // Hangul 音节
		r >= 0xF900 && r <= 0xFAFF,   // CJK 兼容表意
		r >= 0xFE30 && r <= 0xFE4F,   // CJK 兼容形式
		r >= 0xFF00 && r <= 0xFF60,   // 全角形式
		r >= 0xFFE0 && r <= 0xFFE6,   // 全角符号
		r >= 0x20000 && r <= 0x3FFFD: // CJK 扩展 B+
		return true
	}
	return false
}

// humanShort 把 duration 渲染成 5h12m / 45m 这种短格式。
func humanShort(d time.Duration) string {
	d = d.Round(time.Minute)
	h := d / time.Hour
	m := (d % time.Hour) / time.Minute
	if h > 0 {
		return fmt.Sprintf("%dh%dm", h, m)
	}
	return fmt.Sprintf("%dm", m)
}
