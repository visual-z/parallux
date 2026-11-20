package aggregate

import (
	"context"
	"errors"
	"io"
	"net"
	"testing"

	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/adapter/outbound"
	"github.com/sagernet/sing-box/log"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
)

// fakeLink serves an echo over a pipe and records how often it was dialed.
type fakeLink struct {
	outbound.Adapter
	fail  bool
	dials int
}

func newFakeLink(tag string, fail bool) *fakeLink {
	return &fakeLink{Adapter: outbound.NewAdapter("fake", tag, []string{N.NetworkTCP}, nil), fail: fail}
}

func (l *fakeLink) DialContext(ctx context.Context, network string, destination M.Socksaddr) (net.Conn, error) {
	l.dials++
	if l.fail {
		return nil, errors.New(l.Tag() + " down")
	}
	client, server := net.Pipe()
	go func() {
		defer server.Close()
		io.Copy(server, server)
	}()
	return client, nil
}

func (l *fakeLink) ListenPacket(ctx context.Context, destination M.Socksaddr) (net.PacketConn, error) {
	return nil, errors.New("unused")
}

type fakeManager struct {
	adapter.OutboundManager
	outbounds map[string]adapter.Outbound
}

func (m *fakeManager) Outbound(tag string) (adapter.Outbound, bool) {
	o, ok := m.outbounds[tag]
	return o, ok
}

func startAggregate(t *testing.T, options Options, outbounds ...adapter.Outbound) *Outbound {
	t.Helper()
	manager := &fakeManager{outbounds: map[string]adapter.Outbound{}}
	for _, o := range outbounds {
		manager.outbounds[o.Tag()] = o
	}
	o := &Outbound{}
	built, err := newOutbound(manager, log.NewNOPFactory().NewLogger("test"), "agg", options)
	if err != nil {
		t.Fatalf("build aggregate: %v", err)
	}
	o = built
	// Probes would reach the network; the tests drive health directly.
	o.disableProbes = true
	if err := o.Start(adapter.StartStateStart, nil); err != nil {
		t.Fatalf("start aggregate: %v", err)
	}
	t.Cleanup(func() { o.Close() })
	return o
}

func TestTrafficIsCountedPerLink(t *testing.T) {
	a, b := newFakeLink("link-a", false), newFakeLink("link-b", false)
	o := startAggregate(t, Options{Mode: ModeBalance, Links: []string{"link-a", "link-b"}}, a, b)
	for range 2 {
		conn, err := o.DialContext(context.Background(), N.NetworkTCP, M.ParseSocksaddr("example.com:80"))
		if err != nil {
			t.Fatalf("dial: %v", err)
		}
		if _, err := conn.Write([]byte("hello")); err != nil {
			t.Fatalf("write: %v", err)
		}
		buffer := make([]byte, 5)
		if _, err := io.ReadFull(conn, buffer); err != nil {
			t.Fatalf("read: %v", err)
		}
		if a.dials+b.dials == 1 {
			// Keep the first one open to see the active count.
			defer conn.Close()
			continue
		}
		conn.Close()
	}
	if a.dials != 1 || b.dials != 1 {
		t.Fatalf("balance dialed a=%d b=%d, want one each", a.dials, b.dials)
	}
	var stats []GroupStat
	for _, group := range Snapshot() {
		if group.Tag == "agg" {
			stats = append(stats, group)
		}
	}
	if len(stats) != 1 || len(stats[0].Links) != 2 {
		t.Fatalf("Snapshot = %+v, want one group with two links", stats)
	}
	var active int64
	for _, link := range stats[0].Links {
		if link.Upload != 5 || link.Download != 5 {
			t.Fatalf("link %s counted up=%d down=%d, want 5 each", link.Tag, link.Upload, link.Download)
		}
		active += link.Active
	}
	if active != 1 {
		t.Fatalf("active connections = %d, want 1 (one closed, one open)", active)
	}
}

func TestBondModeFallsBackToTheLinksWhenTheBondOutboundFails(t *testing.T) {
	a := newFakeLink("link-a", false)
	bond := newFakeLink("mp", true)
	o := startAggregate(t, Options{Mode: ModeBond, Links: []string{"link-a"}, Bond: "mp"}, a, bond)
	conn, err := o.DialContext(context.Background(), N.NetworkTCP, M.ParseSocksaddr("example.com:80"))
	if err != nil {
		t.Fatalf("dial with a failing bond: %v", err)
	}
	conn.Close()
	if bond.dials != 1 || a.dials != 1 {
		t.Fatalf("dials bond=%d link=%d, want the bond tried first then the link", bond.dials, a.dials)
	}
	bond.fail = false
	conn, err = o.DialContext(context.Background(), N.NetworkTCP, M.ParseSocksaddr("example.com:80"))
	if err != nil {
		t.Fatalf("dial with a working bond: %v", err)
	}
	conn.Close()
	if bond.dials != 2 || a.dials != 1 {
		t.Fatalf("dials bond=%d link=%d, want the working bond to carry it", bond.dials, a.dials)
	}
	if _, err := newOutbound(&fakeManager{}, log.NewNOPFactory().NewLogger("test"), "agg", Options{Mode: ModeBond, Links: []string{"link-a"}}); err == nil {
		t.Fatal("bond mode without a bond outbound was accepted")
	}
}

func TestAggregateRejectsABackupLinkThatIsNotALink(t *testing.T) {
	_, err := newOutbound(&fakeManager{}, log.NewNOPFactory().NewLogger("test"), "agg",
		Options{Mode: ModeFailover, Links: []string{"link-a"}, Backup: []string{"link-z"}})
	if err == nil || !errors.Is(err, err) || !contains(err.Error(), "link-z") {
		t.Fatalf("backup outside links = %v, want an error naming link-z", err)
	}
}

func contains(s, sub string) bool {
	return len(sub) == 0 || (len(s) >= len(sub) && (s == sub || indexOf(s, sub) >= 0))
}

func indexOf(s, sub string) int {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return i
		}
	}
	return -1
}
