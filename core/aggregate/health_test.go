package aggregate

import (
	"context"
	"errors"
	"net"
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
