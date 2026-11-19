package aggregate_test

import (
	"context"
	"io"
	"net"
	"sync/atomic"
	"testing"
	"time"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/adapter/outbound"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/log"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common/json"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
	"github.com/sagernet/sing/protocol/socks"

	"github.com/visual-z/parallux/core/aggregate"
)

// countingLink stands in for a link outbound: it counts dials, can fail, and
// connects to a local echo server whatever the destination.
type countingLink struct {
	outbound.Adapter
	echo  string
	fail  atomic.Bool
	dials atomic.Int64
}

type countingLinkOptions struct{}

var links = map[string]*countingLink{}

func init() {
	include.RegisterOutboundExtension(func(registry *outbound.Registry) {
		outbound.Register[countingLinkOptions](registry, "test-link", func(ctx context.Context, router adapter.Router, logger log.ContextLogger, tag string, _ countingLinkOptions) (adapter.Outbound, error) {
			link := links[tag]
			link.Adapter = outbound.NewAdapter("test-link", tag, []string{N.NetworkTCP}, nil)
			return link, nil
		})
	})
}

func (l *countingLink) DialContext(ctx context.Context, network string, destination M.Socksaddr) (net.Conn, error) {
	l.dials.Add(1)
	if l.fail.Load() {
		return nil, io.ErrClosedPipe
	}
	var dialer net.Dialer
	return dialer.DialContext(ctx, "tcp", l.echo)
}

func (l *countingLink) ListenPacket(ctx context.Context, destination M.Socksaddr) (net.PacketConn, error) {
	return nil, io.ErrClosedPipe
}

func echoServer(t *testing.T) string {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { listener.Close() })
	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			go func() { defer conn.Close(); io.Copy(conn, conn) }()
		}
	}()
	return listener.Addr().String()
}

// startBox runs sing-box with a socks inbound whose only route is the
// aggregate, so every connection goes through the real router.
func startBox(t *testing.T, mode string, failFirst bool) (string, *countingLink, *countingLink) {
	t.Helper()
	echo := echoServer(t)
	a, b := &countingLink{echo: echo}, &countingLink{echo: echo}
	a.fail.Store(failFirst)
	links["link-a"], links["link-b"] = a, b
	port := freePort(t)
	config := `{
	  "log": {"disabled": true},
	  "inbounds": [{"type": "socks", "tag": "in", "listen": "127.0.0.1", "listen_port": ` + port + `}],
	  "outbounds": [
	    {"type": "test-link", "tag": "link-a"},
	    {"type": "test-link", "tag": "link-b"},
	    {"type": "aggregate", "tag": "agg", "mode": "` + mode + `", "links": ["link-a", "link-b"], "probe_targets": ["127.0.0.1:1"]}
	  ],
	  "route": {"final": "agg"}
	}`
	ctx := include.Context(context.Background())
	options, err := json.UnmarshalExtendedContext[option.Options](ctx, []byte(config))
	if err != nil {
		t.Fatalf("parse config: %v", err)
	}
	instance, err := box.New(box.Options{Options: options, Context: ctx})
	if err != nil {
		t.Fatalf("new box: %v", err)
	}
	if err := instance.Start(); err != nil {
		t.Fatalf("start box: %v", err)
	}
	t.Cleanup(func() { instance.Close() })
	return "127.0.0.1:" + port, a, b
}

func freePort(t *testing.T) string {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	_, port, _ := net.SplitHostPort(listener.Addr().String())
	return port
}

func roundTrip(t *testing.T, socksAddr string) {
	t.Helper()
	client := socks.NewClient(N.SystemDialer, M.ParseSocksaddr(socksAddr), socks.Version5, "", "")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	conn, err := client.DialContext(ctx, N.NetworkTCP, M.ParseSocksaddr("example.com:80"))
	if err != nil {
		t.Fatalf("dial through the box: %v", err)
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(5 * time.Second))
	if _, err := conn.Write([]byte("ping")); err != nil {
		t.Fatalf("write: %v", err)
	}
	reply := make([]byte, 4)
	if _, err := io.ReadFull(conn, reply); err != nil {
		t.Fatalf("read echo: %v", err)
	}
}

func TestRoutedConnectionsReachTheAggregateDialer(t *testing.T) {
	socksAddr, a, b := startBox(t, aggregate.ModeBalance, false)
	roundTrip(t, socksAddr)
	roundTrip(t, socksAddr)
	if a.dials.Load() != 1 || b.dials.Load() != 1 {
		t.Fatalf("balance through the router dialed link-a %d and link-b %d times, want one each", a.dials.Load(), b.dials.Load())
	}
	var counted int64
	for _, group := range aggregate.Snapshot() {
		if group.Tag == "agg" {
			for _, link := range group.Links {
				counted += link.Upload
			}
		}
	}
	if counted < 8 {
		t.Fatalf("per-link upload counters total %d bytes through the router, want at least 8", counted)
	}
}

func TestRoutedFailoverSkipsAFailingLink(t *testing.T) {
	socksAddr, a, b := startBox(t, aggregate.ModeFailover, true)
	roundTrip(t, socksAddr)
	if a.dials.Load() == 0 {
		t.Fatal("failover never tried the failing first link; the router bypassed the aggregate")
	}
	if b.dials.Load() != 1 {
		t.Fatalf("failover dialed link-b %d times after link-a failed, want 1", b.dials.Load())
	}
}
