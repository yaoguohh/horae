package runner

import (
	"context"
	"horae/internal/recipe"
	"os"
	"path/filepath"
	"strings"
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
