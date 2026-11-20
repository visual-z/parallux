package aggregate

import (
	"context"
	"encoding/binary"
	"errors"
	"io"
	"math/rand/v2"
	"net"
	"slices"
	"sync"
	"sync/atomic"
	"syscall"
	"testing"
	"time"

	"github.com/sagernet/sing-box/adapter/outbound"
	"github.com/sagernet/sing-box/log"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
)

// packetLink is a link outbound that also carries UDP: every packet conn it
// hands out echoes what is written to it. dialErr, when set, fails TCP dials.
type packetLink struct {
	outbound.Adapter
	dialErr error
	dials   atomic.Int64
	listens atomic.Int64
	last    net.PacketConn
}

func newPacketLink(tag string) *packetLink {
	return &packetLink{Adapter: outbound.NewAdapter("fake", tag, []string{N.NetworkTCP, N.NetworkUDP}, nil)}
}

func (l *packetLink) DialContext(ctx context.Context, network string, destination M.Socksaddr) (net.Conn, error) {
	l.dials.Add(1)
	if l.dialErr != nil {
		return nil, l.dialErr
	}
	client, server := net.Pipe()
	go func() {
		defer server.Close()
		io.Copy(server, server)
	}()
	return client, nil
}

func (l *packetLink) ListenPacket(ctx context.Context, destination M.Socksaddr) (net.PacketConn, error) {
	l.listens.Add(1)
	l.last = &echoPacketConn{packets: make(chan []byte, 8), closed: make(chan struct{})}
	return l.last, nil
}

// echoPacketConn returns each written packet to the next ReadFrom.
type echoPacketConn struct {
	packets chan []byte
	closed  chan struct{}
	once    sync.Once
}

func (c *echoPacketConn) WriteTo(p []byte, addr net.Addr) (int, error) {
	select {
	case c.packets <- slices.Clone(p):
		return len(p), nil
	case <-c.closed:
		return 0, net.ErrClosed
	}
}

func (c *echoPacketConn) ReadFrom(p []byte) (int, net.Addr, error) {
	select {
	case packet := <-c.packets:
		return copy(p, packet), &net.UDPAddr{IP: net.IPv4(203, 0, 113, 9), Port: 443}, nil
	case <-c.closed:
		return 0, nil, net.ErrClosed
	}
}

func (c *echoPacketConn) Close() error                       { c.once.Do(func() { close(c.closed) }); return nil }
func (c *echoPacketConn) LocalAddr() net.Addr                { return &net.UDPAddr{} }
func (c *echoPacketConn) SetDeadline(t time.Time) error      { return nil }
func (c *echoPacketConn) SetReadDeadline(t time.Time) error  { return nil }
func (c *echoPacketConn) SetWriteDeadline(t time.Time) error { return nil }

var localTargets = []string{"192.168.1.10:445", "10.0.0.5:53", "nas.local:445", "printer:631", "[fe80::1]:80", "127.0.0.1:8080"}

func TestRelayLinksNeverCarryLocalDestinations(t *testing.T) {
	link, relay := newPacketLink("link-en7"), newPacketLink("link-relay-1")
	o := startAggregate(t, Options{Mode: ModeBalance, Links: []string{"link-en7", "link-relay-1"}, Relays: []string{"link-relay-1"}}, link, relay)
	ctx := context.Background()
	// Twice each, so balance's rotation would have landed on the relay.
	for _, target := range append(localTargets, localTargets...) {
		conn, err := o.DialContext(ctx, N.NetworkTCP, M.ParseSocksaddr(target))
		if err != nil {
			t.Fatalf("dial %s: %v", target, err)
		}
		conn.Close()
		packets, err := o.ListenPacket(ctx, M.ParseSocksaddr(target))
		if err != nil {
			t.Fatalf("listen packet %s: %v", target, err)
		}
		packets.Close()
	}
	if relay.dials.Load() != 0 || relay.listens.Load() != 0 {
		t.Fatalf("the relay carried %d TCP and %d UDP local destinations, want none", relay.dials.Load(), relay.listens.Load())
	}
	want := int64(2 * len(localTargets))
	if link.dials.Load() != want || link.listens.Load() != want {
		t.Fatalf("the physical link carried %d TCP and %d UDP local destinations, want %d each", link.dials.Load(), link.listens.Load(), want)
	}
	// Public destinations still rotate over both.
	for range 4 {
		conn, err := o.DialContext(ctx, N.NetworkTCP, M.ParseSocksaddr("example.com:443"))
		if err != nil {
			t.Fatalf("dial a public destination: %v", err)
		}
		conn.Close()
	}
	if relay.dials.Load() != 2 {
		t.Fatalf("the relay carried %d of 4 public connections, want 2", relay.dials.Load())
	}
}

func TestALocalDestinationWithOnlyRelaysFailsWithoutDialing(t *testing.T) {
	relay := newPacketLink("link-relay-1")
	o := startAggregate(t, Options{Mode: ModeBalance, Links: []string{"link-relay-1"}, Relays: []string{"link-relay-1"}}, relay)
	if _, err := o.DialContext(context.Background(), N.NetworkTCP, M.ParseSocksaddr("192.168.1.10:445")); err == nil {
		t.Fatal("a local destination was dialed although every link is a relay")
	}
	if relay.dials.Load() != 0 {
		t.Fatalf("the relay was dialed %d times for a local destination, want 0", relay.dials.Load())
	}
}

// INV-12: for a local destination the dial order is the full order with the
// relays removed; for any other destination it is the full order.
func TestLocalDialOrderDropsOnlyRelaysAndKeepsTheRest(t *testing.T) {
	rng := rand.New(rand.NewPCG(24, 12))
	for round := 0; round < 3000; round++ {
		n := rng.IntN(7) // 0 and 1 included
		order := rng.Perm(n)
		relay := make([]bool, n)
		for i := range relay {
			relay[i] = rng.IntN(2) == 0
		}
		if got := relayOrder(slices.Clone(order), relay, false); !slices.Equal(got, order) {
			t.Fatalf("a public destination's order %v became %v", order, got)
		}
		var want []int
		for _, index := range order {
			if !relay[index] {
				want = append(want, index)
			}
		}
		got := relayOrder(slices.Clone(order), relay, true)
		if !slices.Equal(got, want) {
			t.Fatalf("local order of %v with relays %v = %v, want %v", order, relay, got, want)
		}
	}
}

func TestARelayThatRefusesIsSkippedAndMarkedDown(t *testing.T) {
	relay, link := newPacketLink("link-relay-1"), newPacketLink("link-en7")
	// ECONNREFUSED from a relay is the relay's own port, not the destination.
	relay.dialErr = &net.OpError{Op: "dial", Net: "tcp", Err: syscall.ECONNREFUSED}
	o := startAggregate(t, Options{Mode: ModeFailover, Links: []string{"link-relay-1", "link-en7"}, Relays: []string{"link-relay-1"}}, relay, link)
	conn, err := o.DialContext(context.Background(), N.NetworkTCP, M.ParseSocksaddr("example.com:443"))
	if err != nil {
		t.Fatalf("dial with a refusing relay: %v, want the next link to carry it", err)
	}
	conn.Close()
	if relay.dials.Load() != 1 || link.dials.Load() != 1 {
		t.Fatalf("dials relay=%d link=%d, want one each", relay.dials.Load(), link.dials.Load())
	}
	if healthy := o.healthSnapshot(); healthy[0] || !healthy[1] {
		t.Fatalf("health after a refusing relay = %v, want the relay down and the link up", healthy)
	}
	// A physical link's refusal is still the destination's answer.
	link.dialErr = &net.OpError{Op: "dial", Net: "tcp", Err: syscall.ECONNREFUSED}
	relay.dialErr = nil
	o.health[0].healthy.Store(false)
	other := startAggregate(t, Options{Mode: ModeFailover, Links: []string{"link-en7", "link-relay-1"}, Relays: []string{"link-relay-1"}}, link, relay)
	if _, err := other.DialContext(context.Background(), N.NetworkTCP, M.ParseSocksaddr("example.com:443")); !errors.Is(err, syscall.ECONNREFUSED) {
		t.Fatalf("a refusal on a physical link returned %v, want ECONNREFUSED without trying the relay", err)
	}
	// The caller giving up says nothing about the relay.
	if retry, down := relayDialFailure(context.Canceled); retry || down {
		t.Fatalf("relayDialFailure(canceled) = retry %v, down %v, want neither", retry, down)
	}
}

// answeringDialer hands out connections whose far end is `serve`.
type answeringDialer struct {
	serve func(server net.Conn)
	dials atomic.Int64
}

func (d *answeringDialer) DialContext(ctx context.Context, network string, destination M.Socksaddr) (net.Conn, error) {
	d.dials.Add(1)
	client, server := net.Pipe()
	go d.serve(server)
	return client, nil
}

func (d *answeringDialer) ListenPacket(ctx context.Context, destination M.Socksaddr) (net.PacketConn, error) {
	return nil, errors.New("unused")
}

// A relay accepts the dial even when it cannot reach the destination (the
// proxy handshake is lazy; measured on loopback, card 环境假设), so only an
// answer from the far end proves the path.
func TestARelayIsHealthyOnlyWhenARoundTripComesBack(t *testing.T) {
	ctx := context.Background()
	dns := []M.Socksaddr{M.ParseSocksaddr("223.5.5.5:53")}
	dead := &answeringDialer{serve: func(server net.Conn) { server.Close() }}
	if probeOnce(ctx, dead, dns, true) {
		t.Fatal("a relay whose upstream closes at once was probed healthy")
	}
	if !probeOnce(ctx, dead, dns, false) {
		t.Fatal("a physical link that connects must stay healthy: its connect already proves the path")
	}

	var query atomic.Value
	alive := &answeringDialer{serve: func(server net.Conn) {
		defer server.Close()
		var length [2]byte
		if _, err := io.ReadFull(server, length[:]); err != nil {
			return
		}
		message := make([]byte, binary.BigEndian.Uint16(length[:]))
		if _, err := io.ReadFull(server, message); err != nil {
			return
		}
		query.Store(message)
		// A minimal response: the query's header with QR set, no records.
		reply := slices.Clone(message[:12])
		reply[2] |= 0x80
		binary.BigEndian.PutUint16(reply[4:], 0)
		server.Write(append([]byte{0, 12}, reply...))
	}}
	if !probeOnce(ctx, alive, dns, true) {
		t.Fatal("a relay that answers the round trip was probed unhealthy")
	}
	message, _ := query.Load().([]byte)
	if len(message) < 17 || binary.BigEndian.Uint16(message[4:]) != 1 || message[2]&0x80 != 0 {
		t.Fatalf("the round trip sent % x, want a DNS query with one question", message)
	}

	silent := &answeringDialer{serve: func(server net.Conn) {
		defer server.Close()
		io.Copy(io.Discard, server)
	}}
	start := time.Now()
	if probeOnce(ctx, silent, dns, true) {
		t.Fatal("a relay whose upstream never answers was probed healthy")
	}
	if took := time.Since(start); took > probeTimeout+500*time.Millisecond {
		t.Fatalf("a silent relay held the probe for %v, want at most the probe timeout %v", took, probeTimeout)
	}

	// Without a DNS target there is nothing to ask: connecting is all the
	// evidence there is (documented fallback).
	if !probeOnce(ctx, dead, []M.Socksaddr{M.ParseSocksaddr("1.1.1.1:443")}, true) {
		t.Fatal("a relay with no port-53 target must fall back to connect-only")
	}
	// A port-53 target is asked first-class even when listed after another.
	dead.dials.Store(0)
	if probeOnce(ctx, dead, []M.Socksaddr{M.ParseSocksaddr("1.1.1.1:443"), M.ParseSocksaddr("223.5.5.5:53")}, true) {
		t.Fatal("a dead relay passed because a non-DNS target was listed first")
	}
}

func TestRelayPacketsAreCounted(t *testing.T) {
	link, relay := newPacketLink("link-en7"), newPacketLink("link-relay-1")
	o := startAggregate(t, Options{Mode: ModeFailover, Links: []string{"link-relay-1", "link-en7"}, Relays: []string{"link-relay-1"}}, relay, link)
	conn, err := o.ListenPacket(context.Background(), M.ParseSocksaddr("example.com:443"))
	if err != nil {
		t.Fatalf("listen packet: %v", err)
	}
	destination := &net.UDPAddr{IP: net.IPv4(203, 0, 113, 9), Port: 443}
	if _, err := conn.WriteTo([]byte("hello"), destination); err != nil {
		t.Fatalf("write: %v", err)
	}
	buffer := make([]byte, 16)
	n, _, err := conn.ReadFrom(buffer)
	if err != nil || string(buffer[:n]) != "hello" {
		t.Fatalf("read = %q, %v, want the echo", buffer[:n], err)
	}
	stat := func() LinkStat {
		for _, group := range Snapshot() {
			if group.Tag == "agg" {
				return group.Links[0]
			}
		}
		t.Fatal("the aggregate is not in the snapshot")
		return LinkStat{}
	}
	if got := stat(); got.Upload != 5 || got.Download != 5 || got.Active != 1 {
		t.Fatalf("relay counters = up %d, down %d, active %d; want 5, 5, 1", got.Upload, got.Download, got.Active)
	}
	conn.Close()
	conn.Close()
	if got := stat(); got.Active != 0 {
		t.Fatalf("active after closing twice = %d, want 0", got.Active)
	}
	// Physical links are measured at the interface; their packet conns are
	// handed through untouched.
	o.health[0].healthy.Store(false)
	raw, err := o.ListenPacket(context.Background(), M.ParseSocksaddr("example.com:443"))
	if err != nil {
		t.Fatalf("listen packet on the physical link: %v", err)
	}
	if raw != link.last {
		t.Fatalf("the physical link's packet conn was wrapped: %T", raw)
	}
}

func TestAggregateRejectsARelayThatIsNotALink(t *testing.T) {
	_, err := newOutbound(&fakeManager{}, log.NewNOPFactory().NewLogger("test"), "agg",
		Options{Mode: ModeBalance, Links: []string{"link-a"}, Relays: []string{"link-relay-z"}})
	if err == nil || !contains(err.Error(), "link-relay-z") {
		t.Fatalf("relay outside links = %v, want an error naming link-relay-z", err)
	}
}
