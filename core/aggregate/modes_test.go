package aggregate_test

import (
	"context"
	"io"
	"path/filepath"
	"slices"
	"testing"
	"time"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/experimental/clashmode"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/log"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common/json"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
	"github.com/sagernet/sing/protocol/socks"
	"github.com/sagernet/sing/service"
)

// discardLog stands in for the app's log sink. With a platform log writer
// sing-box creates the mode manager, as it does inside the system extension
// (box.go), so the test runs the same mode machinery the app talks to.
type discardLog struct{}

func (discardLog) WriteMessage(level log.Level, message string) {}

// The two rules ParalluxKit's RouteModes adds to a profile that defines no
// modes (pinned there and in testdata/composed-modes.json), in front of a
// small rule set, run by the real router under each mode:
//
//	规则   the profile's own rules decide
//	直连   everything leaves directly
//	全局   everything goes to the proxy, except private addresses, which
//	       fall through to the profile's rules as in 规则
//
// sing-box has no built-in modes: the list it offers is read from the
// clash_mode rules of the configuration, which is why a profile without
// them can only ever be in "Rule".
func TestTheAddedModeRulesRouteByTheSelectedMode(t *testing.T) {
	echo := echoServer(t)
	direct, proxy := &countingLink{echo: echo}, &countingLink{echo: echo}
	links["mode-direct"], links["mode-proxy"] = direct, proxy
	port := freePort(t)
	start := func(rules string) *clashmode.Manager {
		t.Helper()
		config := `{
		  "log": {"disabled": true},
		  "experimental": {"cache_file": {"enabled": true, "path": "` + filepath.Join(t.TempDir(), "cache.db") + `"}},
		  "inbounds": [{"type": "socks", "tag": "in", "listen": "127.0.0.1", "listen_port": ` + port + `}],
		  "outbounds": [
		    {"type": "test-link", "tag": "mode-direct"},
		    {"type": "test-link", "tag": "mode-proxy"}
		  ],
		  "route": {"rules": [` + rules + `
		    {"domain_suffix": ["example.com"], "outbound": "mode-direct"},
		    {"ip_is_private": true, "outbound": "mode-direct"}
		  ], "final": "mode-proxy"}
		}`
		ctx := include.Context(context.Background())
		options, err := json.UnmarshalExtendedContext[option.Options](ctx, []byte(config))
		if err != nil {
			t.Fatalf("parse config: %v", err)
		}
		instance, err := box.New(box.Options{Options: options, Context: ctx, PlatformLogWriter: discardLog{}})
		if err != nil {
			t.Fatalf("new box: %v", err)
		}
		if err := instance.Start(); err != nil {
			t.Fatalf("start box: %v", err)
		}
		t.Cleanup(func() { instance.Close() })
		manager := service.PtrFromContext[clashmode.Manager](ctx)
		if manager == nil {
			t.Fatal("the box has no mode manager")
		}
		return manager
	}

	// Without mode rules the only mode is the default: nothing to switch to.
	bare := start("")
	if got := bare.ModeList(); !slices.Equal(got, []string{"Rule"}) {
		t.Fatalf("a profile without mode rules offers %v, want only Rule", got)
	}
	// Stop it so the port is free for the profile with the added rules.
	// (t.Cleanup closes again; closing twice is harmless.)

	type want struct{ direct, proxy int64 }
	cases := []struct {
		mode        string
		destination string
		want        want
	}{
		{"Rule", "example.com:80", want{direct: 1}}, // the profile's domain rule
		{"Rule", "other.test:80", want{proxy: 1}},   // final
		{"Rule", "10.0.0.5:80", want{direct: 1}},    // the profile's LAN rule
		{"Direct", "example.com:80", want{direct: 1}},
		{"Direct", "other.test:80", want{direct: 1}},
		{"Direct", "10.0.0.5:80", want{direct: 1}},
		{"Global", "example.com:80", want{proxy: 1}},
		{"Global", "other.test:80", want{proxy: 1}},
		{"Global", "10.0.0.5:80", want{direct: 1}}, // the LAN stays with the profile's rules
		// The app sends the name as the core listed it; other cases match too.
		{"global", "example.com:80", want{proxy: 1}},
	}
	port = freePort(t)
	manager := start(`
		    {"clash_mode": "Direct", "outbound": "mode-direct"},
		    {"type": "logical", "mode": "and", "rules": [{"clash_mode": "Global"}, {"ip_is_private": true, "invert": true}], "outbound": "mode-proxy"},`)
	if got := manager.ModeList(); !slices.Equal(got, []string{"Rule", "Global", "Direct"}) {
		t.Fatalf("with the two rules the core offers %v, want Rule, Global, Direct", got)
	}
	client := socks.NewClient(N.SystemDialer, M.ParseSocksaddr("127.0.0.1:"+port), socks.Version5, "", "")
	for _, c := range cases {
		manager.SetMode(c.mode)
		direct.dials.Store(0)
		proxy.dials.Store(0)
		dial, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		conn, err := client.DialContext(dial, N.NetworkTCP, M.ParseSocksaddr(c.destination))
		if err != nil {
			t.Fatalf("%s, %s: dial through the box: %v", c.mode, c.destination, err)
		}
		conn.SetDeadline(time.Now().Add(5 * time.Second))
		conn.Write([]byte("ping"))
		reply := make([]byte, 4)
		if _, err := io.ReadFull(conn, reply); err != nil {
			t.Fatalf("%s, %s: read echo: %v", c.mode, c.destination, err)
		}
		conn.Close()
		cancel()
		if got := (want{direct.dials.Load(), proxy.dials.Load()}); got != c.want {
			t.Errorf("mode %s, %s: dialed direct %d and proxy %d times, want %d and %d", c.mode, c.destination, got.direct, got.proxy, c.want.direct, c.want.proxy)
		}
	}
}

// The app switches modes while the router reads the current one for every
// connection and the reference manager re-reads it on each switch. Both
// must see a whole mode name, never a torn one (fix-clashmode-mode-race):
// under -race this fails while Manager.mode is read without a lock.
func TestSwitchingTheModeWhileItIsReadIsRaceFree(t *testing.T) {
	config := `{
	  "log": {"disabled": true},
	  "experimental": {"cache_file": {"enabled": true, "path": "` + filepath.Join(t.TempDir(), "cache.db") + `"}},
	  "outbounds": [{"type": "direct", "tag": "a"}, {"type": "direct", "tag": "b"}],
	  "route": {"rules": [{"clash_mode": "Global", "outbound": "b"}], "final": "a"}
	}`
	ctx := include.Context(context.Background())
	options, err := json.UnmarshalExtendedContext[option.Options](ctx, []byte(config))
	if err != nil {
		t.Fatalf("parse config: %v", err)
	}
	instance, err := box.New(box.Options{Options: options, Context: ctx, PlatformLogWriter: discardLog{}})
	if err != nil {
		t.Fatalf("new box: %v", err)
	}
	if err := instance.Start(); err != nil {
		t.Fatalf("start box: %v", err)
	}
	t.Cleanup(func() { instance.Close() })
	manager := service.PtrFromContext[clashmode.Manager](ctx)
	if manager == nil {
		t.Fatal("the box has no mode manager")
	}

	const rounds = 200
	modes := []string{"Rule", "Global"}
	done := make(chan []string)
	go func() {
		seen := make([]string, 0, rounds)
		for range rounds {
			seen = append(seen, manager.Mode())
		}
		done <- seen
	}()
	for i := range rounds {
		manager.SetMode(modes[i%2])
	}
	for _, mode := range <-done {
		if !slices.Contains(modes, mode) {
			t.Fatalf("read the mode %q, which is neither Rule nor Global", mode)
		}
	}
}
