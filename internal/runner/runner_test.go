package runner

import (
	"context"
	"horae/internal/recipe"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

func dur(s string) recipe.Duration {
	d, _ := recipe.ParseDuration(s)
	return recipe.Duration(d)
}

func TestRunSuccess(t *testing.T) {
	r := ExecRunner{}
	res := r.Run(context.Background(), recipe.Step{ID: "t", Command: []string{"true"}}, time.Minute, "/usr/bin:/bin")
	if res.Outcome != OutcomeSuccess || res.ExitCode != 0 {
		t.Errorf("got %+v", res)
	}
}

func TestRunFailure(t *testing.T) {
	r := ExecRunner{}
	res := r.Run(context.Background(), recipe.Step{ID: "t", Command: []string{"false"}}, time.Minute, "/usr/bin:/bin")
	if res.Outcome != OutcomeFailure || res.ExitCode != 1 {
		t.Errorf("got %+v", res)
	}
}

func TestRunCapturesStdout(t *testing.T) {
	r := ExecRunner{}
	res := r.Run(context.Background(), recipe.Step{ID: "t", Command: []string{"printf", "hello"}}, time.Minute, "/usr/bin:/bin")
	if !strings.Contains(res.Stdout, "hello") {
		t.Errorf("stdout = %q", res.Stdout)
	}
}

func TestRunTimeout(t *testing.T) {
	r := ExecRunner{}
	step := recipe.Step{ID: "t", Command: []string{"sleep", "5"}, Timeout: dur("100ms")}
	start := time.Now()
	res := r.Run(context.Background(), step, time.Minute, "/usr/bin:/bin")
	if res.Outcome != OutcomeTimeout {
		t.Errorf("expected timeout, got %+v", res)
	}
	if time.Since(start) > 3*time.Second {
		t.Errorf("timeout took too long: %v", time.Since(start))
	}
}

func TestRunShellAndEnv(t *testing.T) {
	r := ExecRunner{}
	step := recipe.Step{ID: "t", Shell: "echo $FOO", Env: map[string]string{"FOO": "bar"}}
	res := r.Run(context.Background(), step, time.Minute, "/usr/bin:/bin")
	if res.Outcome != OutcomeSuccess || !strings.Contains(res.Stdout, "bar") {
		t.Errorf("got %+v", res)
	}
}

func TestRunStepTimeoutFallsBackToDefault(t *testing.T) {
	r := ExecRunner{}
	res := r.Run(context.Background(), recipe.Step{ID: "t", Command: []string{"true"}}, 30*time.Second, "/usr/bin:/bin")
	if res.Outcome != OutcomeSuccess {
		t.Errorf("got %+v", res)
	}
}

// 回归：清空 ambient PATH 后，裸命令必须靠注入的 basePATH 解析（launchd 下的真实场景）。
func TestRunResolvesBareCommandViaBasePATH(t *testing.T) {
	t.Setenv("PATH", "")
	dir := t.TempDir()
	script := filepath.Join(dir, "fakecmd")
	if err := os.WriteFile(script, []byte("#!/bin/sh\necho FAKE_OK\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	r := ExecRunner{}
	res := r.Run(context.Background(), recipe.Step{ID: "t", Command: []string{"fakecmd"}}, time.Minute, dir)
	if res.Outcome != OutcomeSuccess {
		t.Fatalf("bare command should resolve via basePATH, got %+v", res)
	}
	if !strings.Contains(res.Stdout, "FAKE_OK") {
		t.Errorf("stdout = %q", res.Stdout)
	}
}

func TestRunUnknownCommandFails(t *testing.T) {
	r := ExecRunner{}
	res := r.Run(context.Background(), recipe.Step{ID: "t", Command: []string{"definitely-not-a-real-binary-xyz"}}, time.Minute, "/usr/bin:/bin")
	if res.Outcome != OutcomeFailure || !strings.Contains(res.Stderr, "找不到") {
		t.Errorf("unknown command should fail with diagnostic, got %+v", res)
	}
}

// 超时优雅杀：先发 SIGTERM 给整组(让 npm/brew 原子收尾, 避免半装的全局树), 宽限后才 SIGKILL。
// 用一个安装了 TERM 处理器的 perl 子进程验证 SIGTERM 确实先于硬杀送达(旧的直接 SIGKILL 会让
// 处理器没机会运行, marker 不被写出)。perl 比 sh trap 在阻塞期间的信号语义可靠, 且 macOS 自带。
func TestRunGracefulKillSendsSIGTERMFirst(t *testing.T) {
	if _, err := os.Stat("/usr/bin/perl"); err != nil {
		t.Skip("无 perl, 跳过优雅杀验证")
	}
	dir := t.TempDir()
	marker := filepath.Join(dir, "got-term")
	prog := `$SIG{TERM}=sub{open(F,">","` + marker + `");print F "1";close(F);exit 0};sleep 30;`
	r := ExecRunner{}
	step := recipe.Step{ID: "t", Command: []string{"perl", "-e", prog}, Timeout: dur("300ms")}
	start := time.Now()
	res := r.Run(context.Background(), step, time.Minute, "/usr/bin:/bin")
	if res.Outcome != OutcomeTimeout {
		t.Fatalf("expected timeout, got %+v", res)
	}
	if time.Since(start) > 3*time.Second {
		t.Errorf("graceful TERM 路径不应慢到等满 grace: %v", time.Since(start))
	}
	if _, err := os.Stat(marker); err != nil {
		t.Errorf("SIGTERM 处理器未运行(marker 缺失), 说明被直接硬杀: %v", err)
	}
}

// 流式输出：子进程每产出一行(\n 或 \r 分隔)即回调 OnLine, 供菜单栏实时进度。
func TestRunStreamsLinesViaOnLine(t *testing.T) {
	var mu sync.Mutex
	var lines []string
	r := ExecRunner{OnLine: func(id, line string) {
		mu.Lock()
		lines = append(lines, id+":"+line)
		mu.Unlock()
	}}
	step := recipe.Step{ID: "s", Shell: "printf 'alpha\\nbeta\\n'"}
	res := r.Run(context.Background(), step, time.Minute, "/usr/bin:/bin")
	if res.Outcome != OutcomeSuccess {
		t.Fatalf("got %+v", res)
	}
	mu.Lock()
	defer mu.Unlock()
	joined := strings.Join(lines, ",")
	if !strings.Contains(joined, "s:alpha") || !strings.Contains(joined, "s:beta") {
		t.Errorf("expected streamed lines, got %v", lines)
	}
}

// 进度条用 \r 原地刷新, 也要按 \r 切出每次重绘, 否则只看得到最后一行。
func TestRunStreamsCarriageReturnRepaints(t *testing.T) {
	var mu sync.Mutex
	var last string
	r := ExecRunner{OnLine: func(_, line string) {
		mu.Lock()
		last = line
		mu.Unlock()
	}}
	step := recipe.Step{ID: "s", Shell: "printf 'p1\\rp2\\rp3\\n'"}
	res := r.Run(context.Background(), step, time.Minute, "/usr/bin:/bin")
	if res.Outcome != OutcomeSuccess {
		t.Fatalf("got %+v", res)
	}
	mu.Lock()
	defer mu.Unlock()
	if last != "p3" {
		t.Errorf("expected last repaint p3, got %q", last)
	}
}

// 流式不破坏原有的有界尾部捕获: capBuffer 仍保留完整 stdout 供诊断。
func TestRunStreamingKeepsCapturedStdout(t *testing.T) {
	r := ExecRunner{OnLine: func(_, _ string) {}}
	res := r.Run(context.Background(), recipe.Step{ID: "s", Shell: "printf 'hello world\\n'"}, time.Minute, "/usr/bin:/bin")
	if !strings.Contains(res.Stdout, "hello world") {
		t.Errorf("captured stdout = %q", res.Stdout)
	}
}

func TestCapBufferTruncates(t *testing.T) {
	c := &capBuffer{max: 10}
	c.Write([]byte("0123456789ABCDEF")) // 16 字节 > 10
	s := c.String()
	if !strings.Contains(s, "已截断") {
		t.Errorf("should mark truncated: %q", s)
	}
	if !strings.HasSuffix(s, "6789ABCDEF") {
		t.Errorf("should keep last 10 bytes, got %q", s)
	}
}
