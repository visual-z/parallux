package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"io"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
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
)

// Sixteen obviously fake bytes ("0123456789abcdef"); never a real key.
const testRelayKey = "MDEyMzQ1Njc4OWFiY2RlZg=="

func TestTheRelayConfigurationIsAValidShadowsocksServer(t *testing.T) {
	content, err := RelayConfig(RelayOptions{Listen: "::", Port: 39100, Key: testRelayKey})
	if err != nil {
		t.Fatal(err)
	}
	if err := libbox.CheckConfig(string(content)); err != nil {
		t.Fatalf("libbox rejects the generated relay configuration: %v\n%s", err, content)
	}
	for _, want := range []string{`"type": "shadowsocks"`, `"method": "` + RelayMethod + `"`, `"type": "direct"`} {
		if !strings.Contains(string(content), want) {
			t.Fatalf("the relay configuration lacks %s:\n%s", want, content)
		}
	}
}

func TestARelayKeyIsSixteenRandomBytesInStandardBase64(t *testing.T) {
	first, err := NewRelayKey()
	if err != nil {
		t.Fatal(err)
	}
	second, err := NewRelayKey()
	if err != nil {
		t.Fatal(err)
	}
	if first == second {
		t.Fatalf("two generated keys are equal: %q", first)
	}
	raw, err := base64.StdEncoding.DecodeString(first)
	if err != nil || len(raw) != 16 {
		t.Fatalf("NewRelayKey() = %q decodes to %d bytes (%v), want 16 in padded standard base64", first, len(raw), err)
	}
	if _, err := RelayConfig(RelayOptions{Port: 39100, Key: first}); err != nil {
		t.Fatalf("a generated key was refused: %v", err)
	}
	// What sing-box's shadowsocks refuses (measured on loopback, card
	// 环境假设): unpadded, URL-safe alphabet, wrong length.
	refused := map[string]string{
		"unpadded":   strings.TrimRight(testRelayKey, "="),
		"url-safe":   "-_EyMzQ1Njc4OWFiY2RlZg==",
		"32 bytes":   base64.StdEncoding.EncodeToString(make([]byte, 32)),
		"15 bytes":   base64.StdEncoding.EncodeToString(make([]byte, 15)),
		"empty":      "",
		"not base64": "not a key at all!!",
	}
	for name, key := range refused {
		if _, err := RelayConfig(RelayOptions{Port: 39100, Key: key}); err == nil {
			t.Errorf("a %s key was accepted", name)
		}
	}
	if _, err := RelayConfig(RelayOptions{Port: 0, Key: testRelayKey}); err == nil {
		t.Error("port 0 was accepted")
	}
	for _, port := range []uint16{1, 65535} {
		if _, err := RelayConfig(RelayOptions{Port: port, Key: testRelayKey}); err != nil {
			t.Errorf("port %d was refused: %v", port, err)
		}
	}
}

func startBox(t *testing.T, config string) {
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
}

func freePort(t *testing.T) uint16 {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	return uint16(listener.Addr().(*net.TCPAddr).Port)
}

// The whole path on loopback: a client outbound shaped like the one
// ParalluxKit composes (testdata/composed-relay.json), through a relay
// running RelayConfig with a generated key, to an echo server.
func TestARelayCarriesAConnectionForTheOutboundTheAppComposes(t *testing.T) {
	echo, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { echo.Close() })
	go func() {
		for {
			conn, err := echo.Accept()
			if err != nil {
				return
			}
			go func() { defer conn.Close(); io.Copy(conn, conn) }()
		}
	}()

	key, err := NewRelayKey()
	if err != nil {
		t.Fatal(err)
	}
	relayPort, socksPort := freePort(t), freePort(t)
	relay, err := RelayConfig(RelayOptions{Listen: "127.0.0.1", Port: relayPort, Key: key, LogLevel: "error"})
	if err != nil {
		t.Fatal(err)
	}
	startBox(t, string(relay))
	startBox(t, `{
	  "log": {"disabled": true},
	  "inbounds": [{"type": "socks", "tag": "in", "listen": "127.0.0.1", "listen_port": `+strconv.Itoa(int(socksPort))+`}],
	  "outbounds": [
	    {"type": "direct", "tag": "link-lo0", "bind_interface": "lo0"},
	    {"type": "shadowsocks", "tag": "link-relay-1", "server": "127.0.0.1", "server_port": `+strconv.Itoa(int(relayPort))+`,
	     "method": "`+RelayMethod+`", "password": "`+key+`", "detour": "link-lo0"}
	  ],
	  "route": {"final": "link-relay-1"}
	}`)

	client := socks.NewClient(N.SystemDialer, M.ParseSocksaddr("127.0.0.1:"+strconv.Itoa(int(socksPort))), socks.Version5, "", "")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	conn, err := client.DialContext(ctx, N.NetworkTCP, M.ParseSocksaddr(echo.Addr().String()))
	if err != nil {
		t.Fatalf("dial through the relay: %v", err)
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(5 * time.Second))
	if _, err := conn.Write([]byte("ping")); err != nil {
		t.Fatalf("write: %v", err)
	}
	reply := make([]byte, 4)
	if _, err := io.ReadFull(conn, reply); err != nil || string(reply) != "ping" {
		t.Fatalf("echo through the relay = %q, %v", reply, err)
	}

	// A name, not an address: a node's `server` reaches the relay as a
	// name (a detour leaves resolving to the far end), so the relay host
	// resolves it itself, with nothing but its direct outbound.
	_, echoPort, _ := net.SplitHostPort(echo.Addr().String())
	named, err := client.DialContext(ctx, N.NetworkTCP, M.ParseSocksaddr("localhost:"+echoPort))
	if err != nil {
		t.Fatalf("dial a host name through the relay: %v", err)
	}
	defer named.Close()
	named.SetDeadline(time.Now().Add(5 * time.Second))
	if _, err := named.Write([]byte("name")); err != nil {
		t.Fatalf("write to a host name: %v", err)
	}
	if _, err := io.ReadFull(named, reply); err != nil || string(reply) != "name" {
		t.Fatalf("echo from a host name through the relay = %q, %v", reply, err)
	}

	// UDP: QUIC nodes (hysteria2, tuic) and DNS go through the relay as packets.
	udpEcho, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { udpEcho.Close() })
	go func() {
		buffer := make([]byte, 64)
		for {
			n, from, err := udpEcho.ReadFrom(buffer)
			if err != nil {
				return
			}
			udpEcho.WriteTo(buffer[:n], from)
		}
	}()
	packets, err := client.ListenPacket(ctx, M.ParseSocksaddr(udpEcho.LocalAddr().String()))
	if err != nil {
		t.Fatalf("open a packet connection through the relay: %v", err)
	}
	defer packets.Close()
	packets.SetDeadline(time.Now().Add(5 * time.Second))
	if _, err := packets.WriteTo([]byte("udp!"), udpEcho.LocalAddr()); err != nil {
		t.Fatalf("send a packet through the relay: %v", err)
	}
	datagram := make([]byte, 64)
	n, _, err := packets.ReadFrom(datagram)
	if err != nil || string(datagram[:n]) != "udp!" {
		t.Fatalf("packet echo through the relay = %q, %v", datagram[:n], err)
	}
}

func TestTheRelayLinkRoundTripsItsFields(t *testing.T) {
	// A key with every character that needs percent-encoding.
	key := "ab+/cd+/ef+/gh+/ijklmQ=="
	link := RelayLink("2001:db8::21", 39100, key, "worker 1 机房")
	parsed, err := url.Parse(link)
	if err != nil {
		t.Fatalf("RelayLink() = %q does not parse: %v", link, err)
	}
	if parsed.Scheme != "parallux" || parsed.Host != "relay" {
		t.Fatalf("RelayLink() = %q, want parallux://relay?…", link)
	}
	// "+" must travel as %2B: the spec says "+" is not a space. ("=" and
	// "&" are the query's own separators, so the key is checked by value.)
	if strings.ContainsAny(parsed.RawQuery, "+/ ") {
		t.Fatalf("the query %q carries reserved characters unencoded", parsed.RawQuery)
	}
	if !strings.Contains(parsed.RawQuery, "&key=ab%2B%2Fcd%2B%2Fef%2B%2Fgh%2B%2FijklmQ%3D%3D") {
		t.Fatalf("the query %q does not carry the key percent-encoded", parsed.RawQuery)
	}
	// No value carries a raw "=": each pair has exactly the one separator.
	for _, pair := range strings.Split(parsed.RawQuery, "&") {
		if strings.Count(pair, "=") != 1 {
			t.Fatalf("the query pair %q carries a raw \"=\" in its value", pair)
		}
	}
	values, err := url.ParseQuery(parsed.RawQuery)
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]string{"v": "1", "host": "2001:db8::21", "port": "39100", "method": RelayMethod, "key": key}
	for name, value := range want {
		if got := values[name]; len(got) != 1 || got[0] != value {
			t.Errorf("link parameter %s = %q, want exactly %q", name, got, value)
		}
	}
	if len(values) != len(want) {
		t.Errorf("link parameters = %v, want only %d of them", values, len(want))
	}
	if parsed.Fragment != "worker 1 机房" {
		t.Errorf("fragment = %q, want the name", parsed.Fragment)
	}
	if !strings.HasSuffix(link, "#worker%201%20%E6%9C%BA%E6%88%BF") {
		t.Errorf("link = %q, want the name percent-encoded in the fragment", link)
	}
	if bare := RelayLink("10.0.0.21", 1, key, ""); strings.Contains(bare, "#") || !strings.Contains(bare, "host=10.0.0.21") {
		t.Errorf("link without a name = %q, want no fragment", bare)
	}
}

func TestRelayModeGeneratesAKeyOnceAndPrintsTheLink(t *testing.T) {
	keyPath := filepath.Join(t.TempDir(), "relay.key")
	if err := run([]string{"-role", "relay", "-key-file", keyPath, "-generate-key"}); err != nil {
		t.Fatalf("generate key: %v", err)
	}
	info, err := os.Stat(keyPath)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("the key file's mode is %v, want 0600", info.Mode().Perm())
	}
	first, _ := os.ReadFile(keyPath)
	key := strings.TrimSpace(string(first))
	if raw, err := base64.StdEncoding.DecodeString(key); err != nil || len(raw) != 16 {
		t.Fatalf("the generated key file holds %d bytes of key (%v), want 16", len(raw), err)
	}
	if err := run([]string{"-role", "relay", "-key-file", keyPath, "-generate-key"}); err != nil {
		t.Fatalf("generate key again: %v", err)
	}
	if second, _ := os.ReadFile(keyPath); string(second) != string(first) {
		t.Fatal("generating again replaced the existing key")
	}

	var out bytes.Buffer
	stdout = &out
	t.Cleanup(func() { stdout = os.Stdout })
	if err := run([]string{"-role", "relay", "-key-file", keyPath, "-port", "39100", "-host", "10.0.0.21", "-name", "worker-1", "-link"}); err != nil {
		t.Fatalf("print link: %v", err)
	}
	if got, want := strings.TrimSpace(out.String()), RelayLink("10.0.0.21", 39100, key, "worker-1"); got != want || want == "" {
		t.Fatalf("-link printed %q, want %q", got, want)
	}
	if err := run([]string{"-role", "relay", "-key-file", keyPath, "-port", "39100", "-link"}); err == nil || !strings.Contains(err.Error(), "-host") {
		t.Fatalf("-link without -host: err = %v, want it to name -host", err)
	}

	if err := run([]string{"-role", "relay", "-check", "-port", "39101", "-key-file", keyPath}); err != nil {
		t.Fatalf("check mode failed: %v", err)
	}
	if err := run([]string{"-role", "relay", "-check", "-port", "39101"}); err == nil || !strings.Contains(err.Error(), "key-file") {
		t.Fatalf("missing key file: err = %v, want it to name -key-file", err)
	}
	if err := run([]string{"-role", "bogus"}); err == nil || !strings.Contains(err.Error(), "bogus") {
		t.Fatalf("unknown role: err = %v, want it to name the role", err)
	}
	// The key never reaches an error message.
	os.WriteFile(keyPath, []byte("c2hvcnQ=\n"), 0o600)
	if err := run([]string{"-role", "relay", "-check", "-port", "39101", "-key-file", keyPath}); err == nil || strings.Contains(err.Error(), "c2hvcnQ") {
		t.Fatalf("a bad key file: err = %v, want an error that does not quote the key", err)
	}
}
