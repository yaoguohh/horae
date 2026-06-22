package main

import (
	"horae/internal/report"
	"log/slog"
	"sync"
	"time"
)

// progressFlushInterval：实时行写盘节流间隔。下载类输出每秒多行(progress 条按 \r 重绘)，
// 节流避免 current.json 被 temp+rename 刷爆(每次 rename 都会触发菜单栏 app 重读)。
const progressFlushInterval = 500 * time.Millisecond

// maxProgressLines：current.json 里保留的最近实时输出行数(有界环)。折叠态显示末行，展开态显示全部。
const maxProgressLines = 12

// currentWriter 维护"当前在跑的 step"的实时进度(current.json)。OnStepStart 重置，OnLine 节流更新 LastLine。
// runner 的 OnLine 已串行化，此处再用锁兜一层并保护跨 step 的并发可见性。
type currentWriter struct {
	path   string
	logger *slog.Logger
	now    func() time.Time

	mu     sync.Mutex
	cur    report.Current
	lastAt time.Time
}

func newCurrentWriter(path string, logger *slog.Logger) *currentWriter {
	return &currentWriter{path: path, logger: logger, now: time.Now}
}

// start 在某 step 开始时调用：立即写一条 Running=true 的进度(清掉上一步残留的 LastLine)。
// command 非空时作 "$ <cmd>" 首行 seed：npm 类工具在管道下整段静默、仅结尾吐一小撮行，
// 不 seed 则 live 区全程空白、菜单栏无可展开内容；命令即"要执行内容"，先行可见，真实输出再追加其后。
func (c *currentWriter) start(id, label, command string, index, total int) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.cur = report.Current{Running: true, Step: id, Label: label, Index: index, Total: total, StartedAt: c.now()}
	if command != "" {
		c.cur.LastLines = []string{"$ " + command}
	}
	c.flushLocked()
}

// line 在子进程每产出一行时调用：追加到有界环并节流写盘；跨 step 的陈旧行忽略。
func (c *currentWriter) line(id, text string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.cur.Step != id {
		return
	}
	c.cur.LastLines = append(c.cur.LastLines, text)
	// 超出环上限即左移丢最旧；copy-shift 让 backing 数组维持在 maxProgressLines+1，不随 run 时长增长。
	if n := len(c.cur.LastLines); n > maxProgressLines {
		copy(c.cur.LastLines, c.cur.LastLines[n-maxProgressLines:])
		c.cur.LastLines = c.cur.LastLines[:maxProgressLines]
	}
	if c.now().Sub(c.lastAt) < progressFlushInterval {
		return
	}
	c.flushLocked()
}

// flushLocked 写出当前进度并记录时刻；调用方须持锁。
func (c *currentWriter) flushLocked() {
	c.lastAt = c.now()
	if err := report.WriteCurrent(c.path, c.cur); err != nil {
		c.logger.Warn("写 current.json 失败", "err", err)
	}
}
