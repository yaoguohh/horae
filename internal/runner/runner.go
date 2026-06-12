package runner

import (
	"context"
	"errors"
	"fmt"
	"horae/internal/recipe"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

// maxCapture 单个 step stdout/stderr 各自最多保留的尾部字节数，
// 防止刷屏型更新器（进度条等）把输出灌成无界内存。
const maxCapture = 64 * 1024

type Outcome int

const (
	OutcomeSuccess Outcome = iota
	OutcomeFailure
	OutcomeTimeout
)

type Result struct {
	Outcome  Outcome
	ExitCode int
	Duration time.Duration
	Stdout   string
	Stderr   string
}

// Runner 抽象成接口，便于 orchestrator 用 fake 做确定性单测。
type Runner interface {
	Run(ctx context.Context, step recipe.Step, defaultTimeout time.Duration, basePATH string) Result
}

type ExecRunner struct{}

func (ExecRunner) Run(ctx context.Context, step recipe.Step, defaultTimeout time.Duration, basePATH string) Result {
	timeout := step.Timeout.Std()
	if timeout <= 0 {
		timeout = defaultTimeout
	}
	cctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	cmd, err := buildCommand(cctx, step, basePATH)
	if err != nil {
		return Result{Outcome: OutcomeFailure, ExitCode: -1, Stderr: err.Error()}
	}
	cmd.Env = buildEnv(basePATH, step.Env)
	// 独立进程组，超时时整组 kill（brew/npm 会 fork 孙进程）。
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error {
		if cmd.Process == nil {
			return nil
		}
		// 整组已被回收时 Kill 返回 ESRCH，视作已取消，避免 os/exec 误包成 cancel 错误。
		if err := syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL); err != nil && !errors.Is(err, syscall.ESRCH) {
			return err
		}
		return nil
	}
	cmd.WaitDelay = 10 * time.Second
	// stdin 为 nil → exec 自动接 /dev/null，防止交互式更新器等输入挂死。

	stdout := &capBuffer{max: maxCapture}
	stderr := &capBuffer{max: maxCapture}
	cmd.Stdout = stdout
	cmd.Stderr = stderr

	start := time.Now()
	err = cmd.Run()
	elapsed := time.Since(start)

	res := Result{Duration: elapsed, Stdout: stdout.String(), Stderr: stderr.String()}
	switch {
	case errors.Is(cctx.Err(), context.DeadlineExceeded):
		res.Outcome = OutcomeTimeout
		res.ExitCode = -1
	case err != nil:
		res.Outcome = OutcomeFailure
		var ee *exec.ExitError
		if errors.As(err, &ee) {
			res.ExitCode = ee.ExitCode()
		} else {
			res.ExitCode = -1
		}
	default:
		res.Outcome = OutcomeSuccess
		res.ExitCode = 0
	}
	return res
}

// buildCommand 构造待执行命令：shell 模式走 $SHELL -c；命令模式对裸命令（不含路径分隔符）
// 按 basePATH 显式解析二进制（exec.LookPath 只读 ambient PATH 不读 cmd.Env，见 design §10）。
func buildCommand(cctx context.Context, step recipe.Step, basePATH string) (*exec.Cmd, error) {
	if step.Shell != "" {
		sh := os.Getenv("SHELL")
		if sh == "" {
			sh = "/bin/zsh"
		}
		return exec.CommandContext(cctx, sh, "-c", step.Shell), nil
	}
	bin := step.Command[0]
	if !strings.ContainsRune(bin, filepath.Separator) {
		resolved, err := lookPathIn(bin, basePATH)
		if err != nil {
			return nil, fmt.Errorf("在 PATH 下找不到命令 %q：%w", bin, err)
		}
		bin = resolved
	}
	return exec.CommandContext(cctx, bin, step.Command[1:]...), nil
}

// buildEnv：继承当前环境，强制设 PATH（注入 Homebrew 路径），再叠加 step.Env。
func buildEnv(basePATH string, stepEnv map[string]string) []string {
	env := os.Environ()
	env = upsert(env, "PATH", basePATH)
	for k, v := range stepEnv {
		env = upsert(env, k, v)
	}
	return env
}

func upsert(env []string, key, val string) []string {
	prefix := key + "="
	for i, kv := range env {
		if strings.HasPrefix(kv, prefix) {
			env[i] = prefix + val
			return env
		}
	}
	return append(env, prefix+val)
}

// DefaultPATH：在当前 PATH 前置 Homebrew 路径（launchd 下 PATH 近乎空的兜底）。
func DefaultPATH() string {
	brew := "/opt/homebrew/bin:/opt/homebrew/sbin"
	cur := os.Getenv("PATH")
	if cur == "" {
		return brew + ":/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
	}
	if strings.Contains(cur, "/opt/homebrew/bin") {
		return cur
	}
	return brew + ":" + cur
}

// lookPathIn 在给定 PATH（而非进程 ambient PATH）的各目录里查找可执行文件，返回绝对路径。
func lookPathIn(name, pathEnv string) (string, error) {
	for _, dir := range filepath.SplitList(pathEnv) {
		if dir == "" {
			continue
		}
		candidate := filepath.Join(dir, name)
		if info, err := os.Stat(candidate); err == nil && !info.IsDir() && info.Mode()&0o111 != 0 {
			return candidate, nil
		}
	}
	return "", fmt.Errorf("%s 不在 %s 任一目录", name, pathEnv)
}

// capBuffer 是只保留尾部 max 字节的有界 buffer：超过上限即丢弃最早内容并标记截断。
type capBuffer struct {
	max  int
	buf  []byte
	over bool
}

func (c *capBuffer) Write(p []byte) (int, error) {
	c.buf = append(c.buf, p...)
	if len(c.buf) > c.max {
		c.over = true
		c.buf = c.buf[len(c.buf)-c.max:]
	}
	return len(p), nil
}

func (c *capBuffer) String() string {
	if c.over {
		return "…(已截断，仅保留尾部)\n" + string(c.buf)
	}
	return string(c.buf)
}
