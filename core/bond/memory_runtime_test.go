package bond

import (
	"context"
	"math"
	"runtime/debug"
	"testing"

	"github.com/sagernet/sing-box/log"
)

func TestAutomaticRuntimeMemoryLimit(t *testing.T) {
	if got := automaticRuntimeMemoryLimit(1000, 100); got != 900 {
		t.Fatal(got)
	}
	if got := automaticRuntimeMemoryLimit(^uint64(0), ^uint64(0)); got != math.MaxInt64 {
		t.Fatal("overflow", got)
	}
	if got := automaticRuntimeMemoryLimit(0, 100); got != 100 {
		t.Fatal(got)
	}
}

func TestMemoryLoggingStopsWithoutParentCancellation(t *testing.T) {
	previous := debug.SetMemoryLimit(-1)
	for range 10 {
		b := newMemoryBudget(16<<20, false)
		b.startLogging(context.Background(), log.NewNOPFactory().Logger(), "test")
		b.stopLogging()
		b.stopLogging()
		select {
		case <-b.logDone:
		default:
			t.Fatal("budget remains owned by a logging worker")
		}
	}
	if debug.SetMemoryLimit(-1) != previous {
		t.Fatal("service close leaked a process memory guard")
	}
}
