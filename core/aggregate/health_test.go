package aggregate

import (
	"context"
	"errors"
	"net"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	M "github.com/sagernet/sing/common/metadata"
)

// switchDialer fails while `down` is set.
type switchDialer struct{ down atomic.Bool }

func (d *switchDialer) DialContext(ctx context.Context, network string, destination M.Socksaddr) (net.Conn, error) {
	if d.down.Load() {
		return nil, errors.New("link down")
	}
	client, server := net.Pipe()
	server.Close()
	return client, nil
}

func (d *switchDialer) ListenPacket(ctx context.Context, destination M.Socksaddr) (net.PacketConn, error) {
	return nil, errors.New("unused")
}

func waitFor(t *testing.T, limit time.Duration, condition func() bool) time.Duration {
	t.Helper()
	start := time.Now()
	for time.Since(start) < limit {
		if condition() {
			return time.Since(start)
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("condition not met within %v", limit)
	return 0
}

// lossyDialer simulates lost SYNs: the first `lose` dials to each target hang
// until the probe gives up, as a connect whose SYN vanished does; later dials
// succeed. With failFast every dial returns an error at once instead.
type lossyDialer struct {
	mu       sync.Mutex
	lose     int
	failFast bool
	calls    map[string]int
	inFlight atomic.Int32
}

func (d *lossyDialer) DialContext(ctx context.Context, network string, destination M.Socksaddr) (net.Conn, error) {
	d.inFlight.Add(1)
	defer d.inFlight.Add(-1)
	if d.failFast {
		return nil, errors.New("network is unreachable")
	}
	d.mu.Lock()
	if d.calls == nil {
		d.calls = map[string]int{}
	}
	d.calls[destination.String()]++
	lost := d.calls[destination.String()] <= d.lose
	d.mu.Unlock()
	if lost {
		<-ctx.Done()
		return nil, ctx.Err()
	}
	client, server := net.Pipe()
	server.Close()
	return client, nil
}

func (d *lossyDialer) ListenPacket(ctx context.Context, destination M.Socksaddr) (net.PacketConn, error) {
	return nil, errors.New("unused")
}

func probeTargets(n int) []M.Socksaddr {
	all := []M.Socksaddr{M.ParseSocksaddr("192.0.2.1:53"), M.ParseSocksaddr("192.0.2.2:443"), M.ParseSocksaddr("192.0.2.3:53")}
	return all[:n]
}

func TestAProbeSurvivesOneLostConnectionAttempt(t *testing.T) {
	for _, n := range []int{1, 2, 3} {
		dialer := &lossyDialer{lose: 1}
		start := time.Now()
		if !probeOnce(context.Background(), dialer, probeTargets(n)) {
			t.Fatalf("%d target(s), first attempt to each lost: probe failed, want the retry to succeed", n)
		}
		if took := time.Since(start); took >= probeTimeout {
			t.Fatalf("%d target(s): probe took %v, want under probeTimeout %v", n, took, probeTimeout)
		}
		if left := dialer.inFlight.Load(); left != 0 {
			t.Fatalf("%d target(s): %d dial(s) still running after probeOnce returned", n, left)
		}
	}
}

func TestAProbeOfADeadLinkFailsWithinItsTimeoutAndLeavesNoDialRunning(t *testing.T) {
	slack := 200 * time.Millisecond
	for _, n := range []int{0, 1, 3} {
		hanging := &lossyDialer{lose: 1 << 30}
		start := time.Now()
		if probeOnce(context.Background(), hanging, probeTargets(n)) {
			t.Fatalf("%d target(s), every dial hangs: probe succeeded", n)
		}
		if took := time.Since(start); took > probeTimeout+slack {
			t.Fatalf("%d target(s), every dial hangs: probe took %v, want within %v", n, took, probeTimeout+slack)
		}
		if left := hanging.inFlight.Load(); left != 0 {
			t.Fatalf("%d target(s): %d hanging dial(s) still running after probeOnce returned", n, left)
		}

		refused := &lossyDialer{failFast: true}
		start = time.Now()
		if probeOnce(context.Background(), refused, probeTargets(n)) {
			t.Fatalf("%d target(s), every dial errors: probe succeeded", n)
		}
		if took := time.Since(start); took >= probeRetryAfter {
			t.Fatalf("%d target(s), every dial errors at once: probe took %v, want a verdict before the retry at %v", n, took, probeRetryAfter)
		}
	}
}

func TestAFailingLinkIsMarkedUnhealthyWithinTwoSeconds(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	dialer := &switchDialer{}
	health := &linkHealth{}
	health.healthy.Store(true)
	done := make(chan struct{})
	go func() {
		probeLoop(ctx, dialer, []M.Socksaddr{M.ParseSocksaddr("192.0.2.1:53")}, health)
		close(done)
	}()

	dialer.down.Store(true)
	took := waitFor(t, 3*time.Second, func() bool { return !health.healthy.Load() })
	if took > 2*time.Second {
		t.Fatalf("a dead link was marked unhealthy after %v, want within 2s", took)
	}
	dialer.down.Store(false)
	waitFor(t, 4*time.Second, func() bool { return health.healthy.Load() })
	if health.successes < recoverAfter {
		t.Fatalf("recovered after %d successes, want at least %d", health.successes, recoverAfter)
	}
	cancel()
	select {
	case <-done:
	case <-time.After(3 * time.Second):
		t.Fatal("probeLoop did not stop when its context ended")
	}
}
