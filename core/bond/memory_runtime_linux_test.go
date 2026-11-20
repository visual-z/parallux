//go:build linux

package bond

import (
	"math"
	"os"
	"runtime/debug"
	"testing"
)

// Automatic memory detection exists only on Linux (memory_available_linux.go);
// upstream skipped this test at run time elsewhere, a build tag says the same.
func TestRuntimeMemoryGuardOwnership(t *testing.T) {
	t.Setenv("GOMEMLIMIT", "")
	if err := os.Unsetenv("GOMEMLIMIT"); err != nil {
		t.Fatal(err)
	}
	previous := debug.SetMemoryLimit(math.MaxInt64)
	defer debug.SetMemoryLimit(previous)
	var g runtimeMemoryGuard
	limit, automatic, release1, err := g.acquire()
	if err != nil || !automatic || limit <= 0 || limit == math.MaxInt64 {
		t.Fatalf("guard: %d %v %v", limit, automatic, err)
	}
	defer release1()
	limit2, automatic2, release2, err := g.acquire()
	defer release2()
	if err != nil || !automatic2 || limit2 != limit {
		t.Fatal("instances did not share one limit")
	}
	release1()
	release1()
	if debug.SetMemoryLimit(-1) != limit {
		t.Fatal("first close restored a live instance's guard")
	}
	release2()
	if debug.SetMemoryLimit(-1) != math.MaxInt64 {
		t.Fatal("last close did not restore previous setting")
	}

	_, _, release3, err := g.acquire()
	if err != nil {
		t.Fatal(err)
	}
	debug.SetMemoryLimit(2 << 30)
	release3()
	if debug.SetMemoryLimit(-1) != 2<<30 {
		t.Fatal("overwrote a runtime override")
	}
	got, auto, release4, err := g.acquire()
	release4()
	if err != nil || auto || got != 2<<30 {
		t.Fatal("overwrote configured runtime limit")
	}
	debug.SetMemoryLimit(math.MaxInt64)
	t.Setenv("GOMEMLIMIT", "off")
	got, auto, release5, err := g.acquire()
	release5()
	if err != nil || auto || got != math.MaxInt64 {
		t.Fatal("ignored explicit GOMEMLIMIT=off")
	}
}
