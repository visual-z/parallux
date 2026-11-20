package main

import (
	"context"
	stdjson "encoding/json"
	"errors"
	"io"
	"net"
	"net/netip"
	"os"
	"slices"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"testing"
	"time"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/experimental/libbox"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common/json"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
	"github.com/sagernet/sing/protocol/socks"

	"github.com/visual-z/parallux/core/aggregate"
)

// publicNode stands for the address a client knows the server machine by.
// TEST-NET-2 (RFC 5737): never routed, and not a local destination, so the
// client's aggregate bonds it like any real node address.
const publicNode = "198.51.100.7"

// countingEcho is an echo server that counts the connections it accepts.
type countingEcho struct {
	listener net.Listener
	accepted atomic.Int64
}

func newCountingEcho(t *testing.T, address string) *countingEcho {
	t.Helper()
	listener, err := net.Listen("tcp", address)
	if err != nil {
		t.Fatal(err)
	}
	echo := &countingEcho{listener: listener}
	t.Cleanup(func() { listener.Close() })
	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			echo.accepted.Add(1)
			go func() { defer conn.Close(); io.Copy(conn, conn) }()
		}
	}()
	return echo
}

func (e *countingEcho) port() string {
	_, port, _ := net.SplitHostPort(e.listener.Addr().String())
	return port
}

func startBoxInstance(t *testing.T, config string) *box.Box {
	t.Helper()
	ctx := include.Context(context.Background())
	options, err := json.UnmarshalExtendedContext[option.Options](ctx, []byte(config))
	if err != nil {
		t.Fatalf("parse config: %v\n%s", err, config)
	}
	instance, err := box.New(box.Options{Options: options, Context: ctx})
	if err != nil {
		t.Fatalf("new box: %v", err)
	}
	if err := instance.Start(); err != nil {
		t.Fatalf("start box: %v", err)
	}
	t.Cleanup(func() { instance.Close() })
	return instance
}

const selfTestPSK = "self-test-pre-shared-key-0123456789"

// startServer runs the aggregation server exactly as Config builds it.
func startServer(t *testing.T, self []string) string {
	t.Helper()
	port := freePort(t)
	content, err := Config(ConfigOptions{Listen: "127.0.0.1", Port: port, PSK: selfTestPSK, LogLevel: "error", Self: self, SelfTarget: "127.0.0.1"})
	if err != nil {
		t.Fatalf("build the server configuration: %v", err)
	}
	startBoxInstance(t, string(content))
	return strconv.Itoa(int(port))
}

func roundTripThrough(t *testing.T, conn net.Conn, word string) error {
	t.Helper()
	conn.SetDeadline(time.Now().Add(5 * time.Second))
	if _, err := conn.Write([]byte(word)); err != nil {
		return err
	}
	reply := make([]byte, len(word))
	if _, err := io.ReadFull(conn, reply); err != nil {
		return err
	}
	if string(reply) != word {
		return errors.New("echo returned " + strconv.Quote(string(reply)))
	}
	return nil
}

// The whole chain of a node on the aggregation server's own machine, on
// loopback: a node outbound whose `server` is the machine's public address
// detours through the aggregate exactly as ParalluxKit composes it for nodes
// (bond mode, no bypass); the bond carries it to the server; the server
// recognises the address as its own and delivers it to the node's inbound
// on the same machine.
func TestANodeOnTheAggregationServersOwnMachineIsReachedThroughTheBond(t *testing.T) {
	echo := newCountingEcho(t, "127.0.0.1:0")
	serverPort := startServer(t, []string{publicNode})

	// The node: a stock shadowsocks inbound on the same machine.
	nodePort := strconv.Itoa(int(freePort(t)))
	startBoxInstance(t, `{"log":{"disabled":true},
	  "inbounds":[{"type":"shadowsocks","tag":"node-in","listen":"127.0.0.1","listen_port":`+nodePort+`,"method":"`+RelayMethod+`","password":"`+testRelayKey+`"}],
	  "outbounds":[{"type":"direct","tag":"direct"}]}`)

	socksPort := strconv.Itoa(int(freePort(t)))
	startBoxInstance(t, `{"log":{"disabled":true},
	  "inbounds":[{"type":"socks","tag":"in","listen":"127.0.0.1","listen_port":`+socksPort+`}],
	  "outbounds":[
	    {"type":"direct","tag":"link-a","bind_interface":"lo0"},
	    {"type":"direct","tag":"link-b","bind_interface":"lo0"},
	    {"type":"multipath","tag":"parallux-bond","outbounds":["link-a","link-b"],"server":"127.0.0.1","server_port":`+serverPort+`,"psk":"`+selfTestPSK+`"},
	    {"type":"aggregate","tag":"parallux-links","mode":"bond","links":["link-a","link-b"],"bond":"parallux-bond","probe_targets":["127.0.0.1:1"]},
	    {"type":"shadowsocks","tag":"node","server":"`+publicNode+`","server_port":`+nodePort+`,"method":"`+RelayMethod+`","password":"`+testRelayKey+`","detour":"parallux-links"}
	  ],
	  "route":{"final":"node"}}`)

	client := socks.NewClient(N.SystemDialer, M.ParseSocksaddr("127.0.0.1:"+socksPort), socks.Version5, "", "")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	conn, err := client.DialContext(ctx, N.NetworkTCP, M.ParseSocksaddr("127.0.0.1:"+echo.port()))
	if err != nil {
		t.Fatalf("dial through the node: %v", err)
	}
	defer conn.Close()
	if err := roundTripThrough(t, conn, "same machine"); err != nil {
		t.Fatalf("a connection through the node on the server's own machine: %v", err)
	}
	if echo.accepted.Load() != 1 {
		t.Fatalf("the echo server accepted %d connections, want 1", echo.accepted.Load())
	}
	// The bond carried it: the aggregate's own per-link counters only count
	// connections that fell back to a link.
	for _, group := range aggregate.Snapshot() {
		if group.Tag != "parallux-links" {
			continue
		}
		for _, link := range group.Links {
			if link.Upload != 0 || link.Download != 0 || link.Active != 0 {
				t.Fatalf("link %s carried the node's connection itself (up %d, down %d); the bond was bypassed", link.Tag, link.Upload, link.Download)
			}
		}
		return
	}
	t.Fatal("the aggregate is not in the snapshot")
}

// bondThrough builds a client whose multipath outbound reaches the server.
func bondThrough(t *testing.T, serverPort string) N.Dialer {
	t.Helper()
	client := startBoxInstance(t, `{"log":{"disabled":true},"outbounds":[
	  {"type":"direct","tag":"leg0","bind_interface":"lo0"},
	  {"type":"direct","tag":"leg1","bind_interface":"lo0"},
	  {"type":"multipath","tag":"bond","outbounds":["leg0","leg1"],"server":"127.0.0.1","server_port":`+serverPort+`,"psk":"`+selfTestPSK+`"}]}`)
	outbound, ok := client.Outbound().Outbound("bond")
	if !ok {
		t.Fatal("the client box has no bond outbound")
	}
	return outbound
}

// A client that holds the key must still not reach what only this machine
// can: loopback-only panels, the cloud's metadata service, the private
// network. Every form of a loopback address is tried against a listener
// that counts, so a form the rules miss shows up as an accepted connection.
func TestTheServerNeverDialsLoopbackOrPrivateDestinationsForAClient(t *testing.T) {
	echo := newCountingEcho(t, "127.0.0.1:0")
	bond := bondThrough(t, startServer(t, []string{publicNode}))
	for _, target := range []string{
		"127.0.0.1:" + echo.port(),
		"[::ffff:127.0.0.1]:" + echo.port(),
		"localhost:" + echo.port(), // a name that resolves to loopback
		"127.1.2.3:" + echo.port(),
		"0.0.0.0:" + echo.port(),
	} {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		conn, err := bond.DialContext(ctx, N.NetworkTCP, M.ParseSocksaddr(target))
		if err == nil {
			// The bond reports the dial before the server has tried; the
			// refusal arrives as the stream ending.
			if roundTripThrough(t, conn, "ping") == nil {
				t.Errorf("%s: the server relayed a client to its own loopback", target)
			}
			conn.Close()
		}
		cancel()
	}
	if echo.accepted.Load() != 0 {
		t.Fatalf("the loopback listener accepted %d connections relayed for a client, want 0", echo.accepted.Load())
	}
	// The same listener through the machine's public name is the node case
	// and must work: the refusal is about what the client asked for, not
	// about where self delivery lands.
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	conn, err := bond.DialContext(ctx, N.NetworkTCP, M.ParseSocksaddr(publicNode+":"+echo.port()))
	if err != nil {
		t.Fatalf("dial the machine's public address: %v", err)
	}
	defer conn.Close()
	if err := roundTripThrough(t, conn, "ping"); err != nil {
		t.Fatalf("the machine's public address through the bond: %v", err)
	}
}

type rule = map[string]any

func configRules(t *testing.T, o ConfigOptions) ([]rule, []map[string]any) {
	t.Helper()
	content, err := Config(o)
	if err != nil {
		t.Fatalf("Config: %v", err)
	}
	if err := libbox.CheckConfig(string(content)); err != nil {
		t.Fatalf("libbox rejects the configuration: %v\n%s", err, content)
	}
	var parsed struct {
		Outbounds []map[string]any `json:"outbounds"`
		Route     struct {
			Rules []rule `json:"rules"`
		} `json:"route"`
	}
	if err := stdjson.Unmarshal(content, &parsed); err != nil {
		t.Fatal(err)
	}
	return parsed.Route.Rules, parsed.Outbounds
}

func strings_(value any) []string {
	var out []string
	for _, item := range value.([]any) {
		out = append(out, item.(string))
	}
	return out
}

// The order is the contract: names are resolved first so the checks see
// addresses; private destinations are refused before self delivery, which
// itself lands on a private address.
func TestTheServerConfigurationRefusesPrivateDestinationsBeforeDeliveringToItself(t *testing.T) {
	rules, outbounds := configRules(t, ConfigOptions{Listen: "::", Port: 39000, PSK: testPSK,
		Self: []string{"203.0.113.10", "2001:db8::10", "VPS.Example.com."}})
	if len(rules) != 5 {
		t.Fatalf("route rules = %v, want 5", rules)
	}
	if rules[0]["action"] != "resolve" || len(rules[0]) != 1 {
		t.Errorf("rule 0 = %v, want an unconditional resolve", rules[0])
	}
	if rules[1]["ip_is_private"] != true || rules[1]["action"] != "reject" {
		t.Errorf("rule 1 = %v, want private addresses rejected", rules[1])
	}
	// What sing-box's ip_is_private leaves out: carrier-grade NAT space,
	// which holds Alibaba Cloud's metadata service and Tailscale addresses.
	if rules[2]["action"] != "reject" || !slices.Contains(strings_(rules[2]["ip_cidr"]), "100.64.0.0/10") {
		t.Errorf("rule 2 = %v, want 100.64.0.0/10 rejected", rules[2])
	}
	if got := strings_(rules[3]["ip_cidr"]); !slices.Equal(got, []string{"203.0.113.10/32", "2001:db8::10/128"}) || rules[3]["outbound"] != "self" {
		t.Errorf("rule 3 = %v, want the machine's addresses sent to self delivery", rules[3])
	}
	if got := strings_(rules[4]["domain"]); !slices.Equal(got, []string{"vps.example.com"}) || rules[4]["outbound"] != "self" {
		t.Errorf("rule 4 = %v, want the machine's name sent to self delivery", rules[4])
	}
	var self map[string]any
	for _, outbound := range outbounds {
		if outbound["tag"] == "self" {
			self = outbound
		}
	}
	if self == nil || self["type"] != selfType || self["listen_port"] != float64(39000) {
		t.Fatalf("outbounds = %v, want a %s outbound that knows the listen port", outbounds, selfType)
	}

	// Without -self the refusals stay and nothing mentions self delivery.
	rules, outbounds = configRules(t, ConfigOptions{Listen: "::", Port: 39000, PSK: testPSK})
	if len(rules) != 3 || rules[1]["ip_is_private"] != true {
		t.Fatalf("route rules without self = %v, want resolve and the two refusals", rules)
	}
	if len(outbounds) != 1 || outbounds[0]["type"] != "direct" {
		t.Fatalf("outbounds without self = %v, want only direct", outbounds)
	}

	for _, bad := range []string{"203.0.113.10:443", "not a host", "", "vps..example.com", "http://vps.example.com"} {
		if _, err := Config(ConfigOptions{Port: 39000, PSK: testPSK, Self: []string{bad}}); err == nil {
			t.Errorf("self entry %q was accepted", bad)
		}
	}
	if _, err := Config(ConfigOptions{Port: 39000, PSK: testPSK, Self: []string{"203.0.113.10"}, SelfTarget: "not an address"}); err == nil {
		t.Error("a self target that is not an address was accepted")
	}
	// 0, 1 and the limit: more identities than the limit is a mistake.
	many := make([]string, maxSelf+1)
	for i := range many {
		many[i] = "203.0.113." + strconv.Itoa(i+1)
	}
	if _, err := Config(ConfigOptions{Port: 39000, PSK: testPSK, Self: many[:maxSelf]}); err != nil {
		t.Errorf("%d self entries were refused: %v", maxSelf, err)
	}
	if _, err := Config(ConfigOptions{Port: 39000, PSK: testPSK, Self: many}); err == nil {
		t.Errorf("%d self entries were accepted, want at most %d", len(many), maxSelf)
	}
}

// recordingDial answers per address and remembers the order.
type recordingDial struct {
	mu        sync.Mutex
	addresses []string
	deadlines []bool
	fail      map[string]error
	block     map[string]bool
}

func (d *recordingDial) dial(ctx context.Context, network, address string) (net.Conn, error) {
	d.mu.Lock()
	d.addresses = append(d.addresses, address)
	_, bounded := ctx.Deadline()
	d.deadlines = append(d.deadlines, bounded)
	err, block := d.fail[address], d.block[address]
	d.mu.Unlock()
	if block {
		<-ctx.Done()
		return nil, ctx.Err()
	}
	if err != nil {
		return nil, err
	}
	client, server := net.Pipe()
	server.Close()
	return client, nil
}

func sourceIs(address string) func(netip.Addr) (netip.Addr, bool) {
	return func(netip.Addr) (netip.Addr, bool) {
		if address == "" {
			return netip.Addr{}, false
		}
		return netip.MustParseAddr(address), true
	}
}

var refused = &net.OpError{Op: "dial", Net: "tcp", Err: syscall.ECONNREFUSED}

func TestSelfDeliveryTriesTheLocalAddressFirstAndFallsBackToTheAddressGiven(t *testing.T) {
	cases := []struct {
		name        string
		destination string
		source      string
		target      string
		fail        map[string]error
		want        []string
		wantErr     bool
	}{
		{name: "a node listening locally is reached without leaving the machine",
			destination: "203.0.113.10:443", source: "10.0.0.5", want: []string{"10.0.0.5:443"}},
		{name: "nothing listens locally (a forwarder in front, another port): the address as given",
			destination: "203.0.113.10:8443", source: "10.0.0.5", fail: map[string]error{"10.0.0.5:8443": refused},
			want: []string{"10.0.0.5:8443", "203.0.113.10:8443"}},
		{name: "the public address is on an interface: one dial, the kernel delivers it",
			destination: "203.0.113.10:443", source: "203.0.113.10", want: []string{"203.0.113.10:443"}},
		{name: "an explicit target wins over the source address",
			destination: "203.0.113.10:443", source: "10.0.0.5", target: "127.0.0.1", want: []string{"127.0.0.1:443"}},
		{name: "no route to tell the source by: the address as given",
			destination: "203.0.113.10:443", source: "", want: []string{"203.0.113.10:443"}},
		{name: "IPv6",
			destination: "[2001:db8::10]:443", source: "fd00::5", want: []string{"[fd00::5]:443"}},
		{name: "both fail: the error of the address as given",
			destination: "203.0.113.10:443", source: "10.0.0.5",
			fail: map[string]error{"10.0.0.5:443": refused, "203.0.113.10:443": refused},
			want: []string{"10.0.0.5:443", "203.0.113.10:443"}, wantErr: true},
		{name: "a name the router did not resolve, with a target",
			destination: "vps.example.com:443", source: "10.0.0.5", target: "10.0.0.9",
			fail: map[string]error{"10.0.0.9:443": refused}, want: []string{"10.0.0.9:443", "vps.example.com:443"}},
		{name: "a name the router did not resolve, without a target: as given",
			destination: "vps.example.com:443", source: "10.0.0.5", want: []string{"vps.example.com:443"}},
	}
	for _, c := range cases {
		recorder := &recordingDial{fail: c.fail}
		delivery := &selfDelivery{listenPort: 39000, dial: recorder.dial, source: sourceIs(c.source)}
		if c.target != "" {
			delivery.target = netip.MustParseAddr(c.target)
		}
		conn, err := delivery.DialContext(context.Background(), N.NetworkTCP, M.ParseSocksaddr(c.destination))
		if conn != nil {
			conn.Close()
		}
		if (err != nil) != c.wantErr {
			t.Errorf("%s: err = %v, want an error: %v", c.name, err, c.wantErr)
		}
		if !slices.Equal(recorder.addresses, c.want) {
			t.Errorf("%s: dialed %v, want %v", c.name, recorder.addresses, c.want)
		}
	}
}

func TestSelfDeliveryNeverDialsTheServersOwnListener(t *testing.T) {
	recorder := &recordingDial{}
	delivery := &selfDelivery{listenPort: 39000, dial: recorder.dial, source: sourceIs("10.0.0.5")}
	conn, err := delivery.DialContext(context.Background(), N.NetworkTCP, M.ParseSocksaddr("203.0.113.10:39000"))
	if conn != nil {
		conn.Close()
	}
	if err == nil || !strings.Contains(err.Error(), "own listener") {
		t.Fatalf("dialing the server's own listener through itself: err = %v, want a refusal that says so", err)
	}
	if len(recorder.addresses) != 0 {
		t.Fatalf("dialed %v before refusing, want nothing", recorder.addresses)
	}
}

func TestSelfDeliveryBoundsTheLocalAttemptAndRespectsTheCaller(t *testing.T) {
	// A local attempt that hangs (a firewall dropping on loopback) is given
	// up after localDeliveryTimeout, then the address as given is dialed.
	recorder := &recordingDial{block: map[string]bool{"10.0.0.5:443": true}}
	delivery := &selfDelivery{listenPort: 39000, dial: recorder.dial, source: sourceIs("10.0.0.5")}
	start := time.Now()
	conn, err := delivery.DialContext(context.Background(), N.NetworkTCP, M.ParseSocksaddr("203.0.113.10:443"))
	if err != nil {
		t.Fatalf("after a hanging local attempt: %v, want the address as given to carry it", err)
	}
	conn.Close()
	if took := time.Since(start); took > localDeliveryTimeout+time.Second {
		t.Fatalf("a hanging local attempt held the dial for %v, want about %v", took, localDeliveryTimeout)
	}
	if !slices.Equal(recorder.addresses, []string{"10.0.0.5:443", "203.0.113.10:443"}) {
		t.Fatalf("dialed %v, want the local address then the address as given", recorder.addresses)
	}
	if !recorder.deadlines[0] {
		t.Fatal("the local attempt ran without a deadline")
	}

	// The caller giving up ends it: no second dial on a dead context.
	recorder = &recordingDial{block: map[string]bool{"10.0.0.5:443": true}}
	delivery = &selfDelivery{listenPort: 39000, dial: recorder.dial, source: sourceIs("10.0.0.5")}
	ctx, cancel := context.WithCancel(context.Background())
	time.AfterFunc(50*time.Millisecond, cancel)
	if _, err := delivery.DialContext(ctx, N.NetworkTCP, M.ParseSocksaddr("203.0.113.10:443")); !errors.Is(err, context.Canceled) {
		t.Fatalf("a cancelled caller: err = %v, want context.Canceled", err)
	}
	if len(recorder.addresses) != 1 {
		t.Fatalf("dialed %v after the caller gave up, want only the local attempt", recorder.addresses)
	}
}

func TestSelfNamesAlsoCoverTheAddressesTheyResolveTo(t *testing.T) {
	lookups := 0
	lookup := func(ctx context.Context, host string) ([]netip.Addr, error) {
		lookups++
		switch host {
		case "vps.example.com":
			return []netip.Addr{netip.MustParseAddr("203.0.113.10"), netip.MustParseAddr("2001:db8::10"), netip.MustParseAddr("::ffff:203.0.113.10")}, nil
		case "many.example.com":
			var many []netip.Addr
			for i := 1; i <= 40; i++ {
				many = append(many, netip.MustParseAddr("198.51.100."+strconv.Itoa(i)))
			}
			return many, nil
		}
		return nil, errors.New("no such host")
	}
	got := expandSelf(context.Background(), []string{"203.0.113.10", "vps.example.com", "gone.example.com"}, lookup)
	want := []string{"203.0.113.10", "vps.example.com", "gone.example.com", "2001:db8::10"}
	if !slices.Equal(got, want) {
		t.Fatalf("expandSelf = %v, want %v (names kept, new addresses appended once, a failed lookup changes nothing)", got, want)
	}
	if lookups != 2 {
		t.Fatalf("%d lookups, want one per name and none for the address", lookups)
	}
	if got := expandSelf(context.Background(), nil, lookup); len(got) != 0 {
		t.Fatalf("expandSelf(nil) = %v, want nothing", got)
	}
	// A name with many addresses cannot push the list past what Config accepts.
	if got := expandSelf(context.Background(), []string{"many.example.com"}, lookup); len(got) != maxSelf {
		t.Fatalf("a name with 40 addresses expanded to %d entries, want the limit %d", len(got), maxSelf)
	}
}

func TestTheSelfFlagsReachTheConfiguration(t *testing.T) {
	dir := t.TempDir()
	pskPath := dir + "/psk"
	if err := os.WriteFile(pskPath, []byte(testPSK+"\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	// No DNS in tests: the name resolves to a fixed address.
	real := lookupSelf
	lookupSelf = func(ctx context.Context, host string) ([]netip.Addr, error) {
		return []netip.Addr{netip.MustParseAddr("203.0.113.11")}, nil
	}
	t.Cleanup(func() { lookupSelf = real })
	if err := run([]string{"-check", "-port", "39002", "-psk-file", pskPath, "-self", "203.0.113.10, vps.example.com", "-self-target", "10.0.0.5"}); err != nil {
		t.Fatalf("check mode with -self: %v", err)
	}
	if err := run([]string{"-check", "-port", "39002", "-psk-file", pskPath, "-self", "203.0.113.10:443"}); err == nil || !strings.Contains(err.Error(), "203.0.113.10:443") {
		t.Fatalf("a -self entry with a port: err = %v, want it named", err)
	}
}
