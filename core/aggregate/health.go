package aggregate

import (
	"context"
	"sync/atomic"
	"time"

	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
)

// Health-check timing. Why: the PLAN goal is that failover moves new
// connections within 2 s of a link dropping. A probe every second with a 1 s
// timeout marks a dead link unhealthy within at most ~2 s. Assumed values;
// measure on real links in the manual test (D10).
const (
	probeInterval = time.Second
	probeTimeout  = time.Second
	// Why 2: one lucky probe on a flapping link must not bring it back.
	recoverAfter = 2
)

// defaultProbeTargets are tried in order; any success means healthy.
// Assumed reachable from mainland China and abroad (card 环境假设).
var defaultProbeTargets = []M.Socksaddr{
	M.ParseSocksaddr("223.5.5.5:53"),
	M.ParseSocksaddr("1.1.1.1:443"),
}

// linkHealth tracks one link. Only its prober goroutine writes `successes`.
type linkHealth struct {
	healthy atomic.Bool
	// dialFailed is set by markFailed; the prober clears it and restarts its
	// streak, so recovery needs recoverAfter fresh successes.
	dialFailed atomic.Bool
	successes  int
	// relay is set once, before the prober starts (feat-relay-links).
	relay bool
}

// probeLoop probes `dialer` until ctx ends. One probe at a time, so a slow
// link never accumulates goroutines.
func probeLoop(ctx context.Context, dialer N.Dialer, targets []M.Socksaddr, health *linkHealth) {
	ticker := time.NewTicker(probeInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
		if health.dialFailed.Swap(false) {
			health.successes = 0
		}
		if probeOnce(ctx, dialer, targets, health.relay) {
			health.successes++
			if health.successes >= recoverAfter {
				health.healthy.Store(true)
			}
		} else {
			health.successes = 0
			health.healthy.Store(false)
		}
	}
}

// probeOnce succeeds when any target accepts a TCP connection over the link.
// The targets share one probeTimeout so a dead link costs at most one tick.
func probeOnce(ctx context.Context, dialer N.Dialer, targets []M.Socksaddr, roundTrip bool) bool {
	ctx, cancel := context.WithTimeout(ctx, probeTimeout)
	defer cancel()
	for _, target := range targets {
		conn, err := dialer.DialContext(ctx, N.NetworkTCP, target)
		if err == nil {
			conn.Close()
			return true
		}
		if ctx.Err() != nil {
			return false
		}
	}
	return false
}
