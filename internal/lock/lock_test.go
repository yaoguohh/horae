package lock

import (
	"errors"
	"path/filepath"
	"testing"
	"time"
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

// AcquireBlocking 撞锁时应阻塞等待, 锁释放后再拿到(供 app 手动触发的 run 排队而非静默丢弃)。
func TestAcquireBlockingWaitsThenAcquires(t *testing.T) {
	path := filepath.Join(t.TempDir(), "x.lock")
	l1, err := Acquire(path)
	if err != nil {
		t.Fatal(err)
	}

	got := make(chan *Lock, 1)
	go func() {
		l, err := AcquireBlocking(path)
		if err != nil {
			t.Errorf("AcquireBlocking err: %v", err)
		}
		got <- l
	}()

	// 持锁期间不应返回。
	select {
	case <-got:
		t.Fatal("AcquireBlocking 在锁被持有时不应返回")
	case <-time.After(100 * time.Millisecond):
	}

	if err := l1.Release(); err != nil {
		t.Fatal(err)
	}

	// 释放后应及时拿到。
	select {
	case l := <-got:
		if l == nil {
			t.Fatal("AcquireBlocking 释放后应拿到锁")
		}
		l.Release()
	case <-time.After(2 * time.Second):
		t.Fatal("AcquireBlocking 在锁释放后应及时返回")
	}
}
