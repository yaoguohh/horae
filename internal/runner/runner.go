package runner

import (
	"context"
	"errors"
	"fmt"
	"horae/internal/recipe"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
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

type ExecRunner struct {
	// OnLine 若非 nil，子进程每产出一行（以 \n 或 \r 分隔）即回调一次，用于实时进度（菜单栏 app）。
	// 与有界 capBuffer 并存：capBuffer 仍保留尾部供超时/失败诊断，OnLine 只镜像不缓冲。
	// 可能被 stdout/stderr 两个 goroutine 并发触发，Run 内部已串行化，consumer 无需自行加锁。
	OnLine func(stepID, line string)
}

func (r ExecRunner) Run(ctx context.Context, step recipe.Step, defaultTimeout time.Duration, basePATH string) Result {
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
	// 独立进程组，超时时整组先 SIGTERM 后 SIGKILL（brew/npm 会 fork 孙进程）。
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	var killTimer *time.Timer
	cmd.Cancel = func() error {
		t, cerr := gracefulStop(cmd)
		killTimer = t
		return cerr
	}
	cmd.WaitDelay = gracefulKillDelay + 2*time.Second
	// stdin 为 nil → exec 自动接 /dev/null，防止交互式更新器等输入挂死。

	stdout := &capBuffer{max: maxCapture}
	stderr := &capBuffer{max: maxCapture}
	cmd.Stdout, cmd.Stderr = r.wrapOutput(step.ID, stdout, stderr)

	start := time.Now()
	err = cmd.Run()
	elapsed := time.Since(start)
	// 进程已回收：若优雅退出（SIGTERM 后自行收尾），停掉兜底 SIGKILL 定时器，
	// 杜绝 grace 期满后向已被复用的 pgid 误发 SIGKILL。cmd.Wait 已等齐 Cancel goroutine，读 killTimer 安全。
	if killTimer != nil {
		killTimer.Stop()
	}

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

// gracefulKillDelay：超时后先给整组 SIGTERM，留这么长宽限让 npm/brew 原子收尾（回滚 in-flight
// 安装，避免半装的全局树），仍不退出才 SIGKILL 整组。WaitDelay 只能 KILL 直接子进程、覆盖不到孙进程，
// 故这里显式杀整组。
const gracefulKillDelay = 5 * time.Second

// gracefulStop 先向进程组发 SIGTERM，返回一个在宽限期后兜底 SIGKILL 整组的定时器（供调用方在进程
// 回收后 Stop）。整组已退出（ESRCH）则直接返回，避免 os/exec 误把它当 cancel 错误。
func gracefulStop(cmd *exec.Cmd) (*time.Timer, error) {
	if cmd.Process == nil {
		return nil, nil
	}
	pgid := -cmd.Process.Pid
	if err := syscall.Kill(pgid, syscall.SIGTERM); err != nil {
		if errors.Is(err, syscall.ESRCH) {
			return nil, nil
		}
		return nil, err
	}
	return time.AfterFunc(gracefulKillDelay, func() { _ = syscall.Kill(pgid, syscall.SIGKILL) }), nil
}

// wrapOutput 在有界 capBuffer 之上叠加按行回调（仅当 OnLine 非 nil）。stdout/stderr 各由独立
// goroutine 写入、各持自己的 lineWriter buf，两路共用一把锁串行化 OnLine，consumer 无需自行加锁。
func (r ExecRunner) wrapOutput(stepID string, stdout, stderr *capBuffer) (io.Writer, io.Writer) {
	if r.OnLine == nil {
		return stdout, stderr
	}
	var mu sync.Mutex
	sink := func(line string) {
		mu.Lock()
		r.OnLine(stepID, line)
		mu.Unlock()
	}
	return io.MultiWriter(stdout, &lineWriter{sink: sink}), io.MultiWriter(stderr, &lineWriter{sink: sink})
}

// maxLineCapture：无换行的超长输出下，单行最多累积这么多字节就强制切一次，防止无界增长。
const maxLineCapture = 8 * 1024

// lineWriter 把写入按 \n 或 \r 切成行，对每个非空行调用 sink。progress 条用 \r 原地重绘，
// 按 \r 切才能反映实时进度。只镜像不落盘（落盘仍由 capBuffer 负责）。
type lineWriter struct {
	sink func(string)
	buf  []byte
}

func (w *lineWriter) Write(p []byte) (int, error) {
	for _, b := range p {
		if b == '\n' || b == '\r' {
			w.flush()
			continue
		}
		w.buf = append(w.buf, b)
		if len(w.buf) >= maxLineCapture {
			w.flush()
		}
	}
	return len(p), nil
}

func (w *lineWriter) flush() {
	line := strings.TrimSpace(string(w.buf))
	w.buf = w.buf[:0]
	if line != "" {
		w.sink(line)
	}
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
