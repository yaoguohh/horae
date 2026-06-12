package lock

import (
	"errors"
	"path/filepath"
	"testing"
)

func TestAcquireReleaseReacquire(t *testing.T) {
	path := filepath.Join(t.TempDir(), "x.lock")
	l, err := Acquire(path)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := Acquire(path); !errors.Is(err, ErrLocked) {
		t.Errorf("second Acquire err = %v, want ErrLocked", err)
	}
	if err := l.Release(); err != nil {
		t.Fatal(err)
	}
	l2, err := Acquire(path)
	if err != nil {
		t.Fatalf("re-acquire after release failed: %v", err)
	}
	l2.Release()
}
