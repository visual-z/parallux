package aggregate

import (
	"context"
	"strings"
	"sync"

	"github.com/sagernet/sing-box/adapter"
	M "github.com/sagernet/sing/common/metadata"
)

// One prober per link outbound, shared by every aggregate outbound that
// uses it.
//
// A composed profile has several aggregates over the same links (one in
// place of each of the user's direct outbounds, plus parallux-links). Each
// used to probe every link itself: the same question asked once per group
// every second, and for a relay link each question is a DNS round trip
// through the relay host. Sharing also shares the evidence: a dial failure
// one group sees marks the link down for all of them.
//
// The key is the outbound object, not its tag: a reloaded core builds new
// outbounds under the same tags, and a prober must never outlive the
// outbound it dials through.
type proberKey struct {
	link    adapter.Outbound
	targets string
	relay   bool
}

type sharedProber struct {
	health *linkHealth
	users  int
	cancel context.CancelFunc
	done   chan struct{}
}

var (
	probersLock sync.Mutex
	probers     = map[proberKey]*sharedProber{}
)

// acquireProber returns the health of `link`, starting its prober if this
// is the first user, and the function that gives it back. The prober stops
// when its last user releases it; release waits for it to finish, so no
// probe runs after the last aggregate has closed.
func acquireProber(link adapter.Outbound, targets []M.Socksaddr, relay bool) (*linkHealth, func()) {
	names := make([]string, len(targets))
	for i, target := range targets {
		names[i] = target.String()
	}
	key := proberKey{link: link, targets: strings.Join(names, ","), relay: relay}

	probersLock.Lock()
	prober := probers[key]
	if prober == nil {
		ctx, cancel := context.WithCancel(context.Background())
		prober = &sharedProber{health: &linkHealth{relay: relay}, cancel: cancel, done: make(chan struct{})}
		// Optimistic until the first probe says otherwise, so the first
		// connections after start do not wait for a probe round.
		prober.health.healthy.Store(true)
		probers[key] = prober
		go func() {
			defer close(prober.done)
			probeLoop(ctx, link, targets, prober.health)
		}()
	}
	prober.users++
	probersLock.Unlock()

	var once sync.Once
	return prober.health, func() {
		once.Do(func() {
			probersLock.Lock()
			prober.users--
			last := prober.users == 0
			if last {
				delete(probers, key)
			}
			probersLock.Unlock()
			if last {
				prober.cancel()
				<-prober.done
			}
		})
	}
}
