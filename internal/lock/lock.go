package lock

import (
	"errors"
	"os"
	"path/filepath"
	"syscall"
)

var ErrLocked = errors.New("horae already running")

type Lock struct{ f *os.File }

// Acquire 取单实例锁, 撞锁立即返回 ErrLocked(launchd/cadence 触发用: 上一轮在跑就跳过本次)。
func Acquire(path string) (*Lock, error) {
	return acquire(path, syscall.LOCK_EX|syscall.LOCK_NB)
}

// AcquireBlocking 取单实例锁, 撞锁时阻塞等待上一轮结束再拿到(app 手动触发用: 排队而非静默丢弃)。
func AcquireBlocking(path string) (*Lock, error) {
	return acquire(path, syscall.LOCK_EX)
}

func acquire(path string, how int) (*Lock, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return nil, err
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return nil, err
	}
	if err := syscall.Flock(int(f.Fd()), how); err != nil {
		_ = f.Close()
		if errors.Is(err, syscall.EWOULDBLOCK) {
			return nil, ErrLocked
		}
		return nil, err
	}
	return &Lock{f: f}, nil
}

func (l *Lock) Release() error {
	unlockErr := syscall.Flock(int(l.f.Fd()), syscall.LOCK_UN)
	closeErr := l.f.Close()
	return errors.Join(unlockErr, closeErr)
}
