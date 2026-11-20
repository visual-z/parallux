package aggregate

import (
	"context"
	"io"
	"net"
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
//
// roundTrip (relay links): the connection must also bring an answer back,
// because a relay host accepts the dial whether or not it can reach the
// target (feat-relay-links, 环境假设). Only port-53 targets can be asked; with
// none configured, connecting is all the evidence there is.
func probeOnce(ctx context.Context, dialer N.Dialer, targets []M.Socksaddr, roundTrip bool) bool {
	ctx, cancel := context.WithTimeout(ctx, probeTimeout)
	defer cancel()
	if roundTrip {
		if dns := dnsTargets(targets); len(dns) > 0 {
			targets = dns
		} else {
			roundTrip = false
		}
	}
	for _, target := range targets {
		conn, err := dialer.DialContext(ctx, N.NetworkTCP, target)
		if err == nil {
			ok := !roundTrip || answers(ctx, conn)
			conn.Close()
			if ok {
				return true
			}
		}
		if ctx.Err() != nil {
			return false
		}
	}
	return false
}

func dnsTargets(targets []M.Socksaddr) []M.Socksaddr {
	var dns []M.Socksaddr
	for _, target := range targets {
		if target.Port == 53 {
			dns = append(dns, target)
		}
	}
	return dns
}

// rootQuery is a DNS query for the root's NS records in TCP framing: a
// 2-byte length, the 12-byte header (id "PX", recursion desired, one
// question), the root name, type NS, class IN. Every resolver answers it
// with something, and only that an answer comes back matters.
var rootQuery = []byte{
	0, 17,
	'P', 'X', 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0,
	0,
	0, 2, 0, 1,
}

// answers sends rootQuery and reports whether the far end replied before
// ctx ends. The reply is not parsed: its length prefix arriving is what
// proves the path through the relay.
func answers(ctx context.Context, conn net.Conn) bool {
	if deadline, ok := ctx.Deadline(); ok {
		conn.SetDeadline(deadline)
	}
	// Cancellation (the core stopping or reloading) must end the read at
	// once, not at the deadline: closing waits for every prober, and a
	// second per silent relay adds up.
	stop := context.AfterFunc(ctx, func() { conn.Close() })
	defer stop()
	if _, err := conn.Write(rootQuery); err != nil {
		return false
	}
	var length [2]byte
	_, err := io.ReadFull(conn, length[:])
	return err == nil
}
