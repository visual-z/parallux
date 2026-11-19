package aggregate

import (
	"context"
	"errors"
	"fmt"
	"net"
	"os"
	"syscall"
	"testing"

	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/adapter/outbound"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
)

func opError(errno syscall.Errno) error {
	return &net.OpError{Op: "dial", Net: "tcp", Err: os.NewSyscallError("connect", errno)}
}

func TestDialFailuresMarkOnlyTheLinkThatFailed(t *testing.T) {
	cases := []struct {
		name            string
		err             error
		retry, linkDown bool
	}{
		{"refused", opError(syscall.ECONNREFUSED), false, false},
		{"reset", opError(syscall.ECONNRESET), false, false},
		{"timeout", opError(syscall.ETIMEDOUT), true, false},
		{"deadline", context.DeadlineExceeded, true, false},
		{"host unreachable", opError(syscall.EHOSTUNREACH), true, false},
		{"network unreachable", opError(syscall.ENETUNREACH), true, true},
		{"network down", opError(syscall.ENETDOWN), true, true},
		{"address gone", opError(syscall.EADDRNOTAVAIL), true, true},
		{"no device", opError(syscall.ENXIO), true, true},
		{"no interface", fmt.Errorf("bind: %w", errors.New("no such network interface")), true, true},
		{"cancelled", context.Canceled, false, false},
		{"wrapped cancel", fmt.Errorf("dial: %w", context.Canceled), false, false},
		{"unknown", errors.New("tls: handshake failure"), true, false},
	}
	for _, c := range cases {
		retry, down := dialFailure(c.err)
		if retry != c.retry || down != c.linkDown {
			t.Errorf("%s: dialFailure = (retry %v, down %v), want (%v, %v)", c.name, retry, down, c.retry, c.linkDown)
		}
	}
}

// erringLink fails every dial with err.
type erringLink struct {
	outbound.Adapter
	err   error
	dials int
}

func (l *erringLink) DialContext(context.Context, string, M.Socksaddr) (net.Conn, error) {
	l.dials++
	return nil, l.err
}

func (l *erringLink) ListenPacket(context.Context, M.Socksaddr) (net.PacketConn, error) {
	l.dials++
	return nil, l.err
}

func newErringLink(tag string, err error) *erringLink {
	return &erringLink{Adapter: outbound.NewAdapter("fake", tag, []string{N.NetworkTCP, N.NetworkUDP}, nil), err: err}
}

func TestARefusedDestinationLeavesEveryLinkHealthy(t *testing.T) {
	a, b := newErringLink("link-a", opError(syscall.ECONNREFUSED)), newErringLink("link-b", opError(syscall.ECONNREFUSED))
	o := startAggregate(t, Options{Mode: ModeBalance, Links: []string{"link-a", "link-b"}}, a, b)
	if _, err := o.DialContext(context.Background(), N.NetworkTCP, M.ParseSocksaddr("198.51.100.1:81")); err == nil {
		t.Fatal("dial succeeded, want the refusal")
	}
	if a.dials+b.dials != 1 {
		t.Errorf("dialed %d times, want 1: a refusal is the destination's answer", a.dials+b.dials)
	}
	for i, healthy := range o.healthSnapshot() {
		if !healthy {
			t.Errorf("link %d marked unhealthy by a refused destination", i)
		}
	}

	down := newErringLink("link-c", opError(syscall.ENETDOWN))
	up := newFakeLink("link-d", false)
	o2 := startAggregate(t, Options{Mode: ModeFailover, Links: []string{"link-c", "link-d"}}, adapter.Outbound(down), up)
	conn, err := o2.DialContext(context.Background(), N.NetworkTCP, M.ParseSocksaddr("example.com:80"))
	if err != nil {
		t.Fatalf("dial with one link down: %v", err)
	}
	conn.Close()
	if health := o2.healthSnapshot(); health[0] || !health[1] {
		t.Errorf("health = %v, want only the down link marked", health)
	}
}

func TestSnapshotIsSortedByGroupTag(t *testing.T) {
	var outs []adapter.Outbound
	for _, tag := range []string{"zz-1", "aa-1", "mm-1"} {
		outs = append(outs, newFakeLink("l-"+tag, false))
	}
	for i, tag := range []string{"zz-agg", "aa-agg", "mm-agg"} {
		link := outs[i]
		manager := &fakeManager{outbounds: map[string]adapter.Outbound{link.Tag(): link}}
		built, err := newOutbound(manager, nil, tag, Options{Mode: ModeFailover, Links: []string{link.Tag()}})
		if err != nil {
			t.Fatal(err)
		}
		built.disableProbes = true
		if err := built.Start(adapter.StartStateStart, nil); err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { built.Close() })
	}
	for range 20 {
		var tags []string
		for _, group := range Snapshot() {
			tags = append(tags, group.Tag)
		}
		for i := 1; i < len(tags); i++ {
			if tags[i-1] > tags[i] {
				t.Fatalf("Snapshot order %v is not sorted", tags)
			}
		}
	}
}
