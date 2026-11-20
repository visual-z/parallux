package bond_test

import (
	"bytes"
	"context"
	"io"
	"net"
	"strconv"
	"testing"
	"time"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common/json"
	M "github.com/sagernet/sing/common/metadata"

	_ "github.com/visual-z/parallux/core/bond"
)

// Why 20 s: a loopback session handshakes in milliseconds; the bound only
// keeps a broken port from hanging the test run.
const loopbackTimeout = 20 * time.Second

func freePort(t *testing.T) int {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	return listener.Addr().(*net.TCPAddr).Port
}

func startBox(t *testing.T, ctx context.Context, config string) *box.Box {
	t.Helper()
	ctx = include.Context(ctx)
	options, err := json.UnmarshalExtendedContext[option.Options](ctx, []byte(config))
	if err != nil {
		t.Fatalf("decode config: %v\n%s", err, config)
	}
	instance, err := box.New(box.Options{Context: ctx, Options: options})
	if err != nil {
		t.Fatalf("create box: %v", err)
	}
	if err := instance.Start(); err != nil {
		instance.Close()
		t.Fatalf("start box: %v", err)
	}
	t.Cleanup(func() { instance.Close() })
	return instance
}

// An echo server stands in for the destination; the client box dials it
// through its multipath outbound, two loopback legs, and the server box's
// multipath inbound, whose direct outbound reaches the echo server.
func TestAMultipathConnectionOverTwoLoopbackLegsRoundTripsBytes(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), loopbackTimeout)
	defer cancel()

	echo, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer echo.Close()
	go func() {
		for {
			conn, err := echo.Accept()
			if err != nil {
				return
			}
			go func() {
				defer conn.Close()
				io.Copy(conn, conn)
			}()
		}
	}()

	serverPort := strconv.Itoa(freePort(t))
	psk := "loopback-test-pre-shared-key-0123456789"
	startBox(t, ctx, `{
  "log": {"level": "warn"},
  "inbounds": [{"type": "multipath", "tag": "mp-in", "listen": "127.0.0.1", "listen_port": `+serverPort+`, "psk": "`+psk+`"}],
  "outbounds": [{"type": "direct", "tag": "direct"}]
}`)
	client := startBox(t, ctx, `{
  "log": {"level": "warn"},
  "outbounds": [
    {"type": "direct", "tag": "leg0"},
    {"type": "direct", "tag": "leg1"},
    {"type": "multipath", "tag": "bond", "outbounds": ["leg0", "leg1"], "server": "127.0.0.1", "server_port": `+serverPort+`, "psk": "`+psk+`"}
  ]
}`)

	outbound, ok := client.Outbound().Outbound("bond")
	if !ok {
		t.Fatal("the client box has no bond outbound")
	}
	conn, err := outbound.DialContext(ctx, "tcp", M.ParseSocksaddr(echo.Addr().String()))
	if err != nil {
		t.Fatalf("dial the echo server through multipath: %v", err)
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(loopbackTimeout))

	// About 64 KiB: more than one multipath frame.
	payload := bytes.Repeat([]byte("parallux bond "), (64<<10)/14)
	go conn.Write(payload)
	got := make([]byte, len(payload))
	if _, err := io.ReadFull(conn, got); err != nil {
		t.Fatalf("read the echoed bytes back: %v", err)
	}
	if !bytes.Equal(got, payload) {
		t.Fatalf("the echoed bytes differ from the %d bytes sent", len(payload))
	}
}
