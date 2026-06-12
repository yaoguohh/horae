package lock

import (
	"errors"
	"os"
	"path/filepath"
	"syscall"
)

var ErrLocked = errors.New("horae already running")

type Lock struct{ f *os.File }

func Acquire(path string) (*Lock, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return nil, err
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return nil, err
	}
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
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
