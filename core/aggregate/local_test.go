package aggregate

import (
	"context"
	"testing"

	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
)

func TestLocalDestinationsNeverGoThroughTheBond(t *testing.T) {
	bypass := []string{"Bond.Example.com", "203.0.113.7"}
	cases := map[string]bool{
		"10.0.0.5:445":          false,
		"172.16.1.1:80":         false,
		"172.31.255.254:80":     false,
		"192.168.1.10:9000":     false,
		"127.0.0.1:8080":        false,
		"169.254.10.1:80":       false,
		"100.64.0.1:22":         false,
		"100.127.255.254:22":    false,
		"224.0.0.251:5353":      false,
		"0.0.0.0:80":            false,
		"[::1]:80":              false,
		"[fe80::1]:80":          false,
		"[fd00::1]:80":          false,
		"[ff02::fb]:5353":       false,
		"nas.local:445":         false,
		"router.lan:80":         false,
		"printer.home.arpa:631": false,
		"git.corp.internal:22":  false,
		"nas:445":               false,
		"bond.example.com:443":  false,
		"203.0.113.7:8443":      false,
		"172.32.0.1:80":         true,
		"100.128.0.1:80":        true,
		"8.8.8.8:443":           true,
		"[2606:4700::1111]:443": true,
		"www.baidu.com:443":     true,
		"example.com:80":        true,
	}
	for address, want := range cases {
		if got := bondEligible(M.ParseSocksaddr(address), bypass); got != want {
			t.Errorf("bondEligible(%s) = %v, want %v", address, got, want)
		}
	}
	if !bondEligible(M.ParseSocksaddr("example.com:80"), nil) {
		t.Error("a nil bypass list must not exclude public destinations")
	}
}

func TestBondSkipsLocalDestinations(t *testing.T) {
	a := newFakeLink("link-a", false)
	bond := newFakeLink("mp", false)
	o := startAggregate(t, Options{Mode: ModeBond, Links: []string{"link-a"}, Bond: "mp", BondBypass: []string{"vps.example.com"}}, a, bond)
	for _, target := range []string{"192.168.1.10:445", "nas.local:445", "vps.example.com:22"} {
		conn, err := o.DialContext(context.Background(), N.NetworkTCP, M.ParseSocksaddr(target))
		if err != nil {
			t.Fatalf("dial %s: %v", target, err)
		}
		conn.Close()
	}
	if bond.dials != 0 || a.dials != 3 {
		t.Fatalf("local dials went bond=%d link=%d, want 0 and 3", bond.dials, a.dials)
	}
	conn, err := o.DialContext(context.Background(), N.NetworkTCP, M.ParseSocksaddr("www.baidu.com:443"))
	if err != nil {
		t.Fatalf("dial public: %v", err)
	}
	conn.Close()
	if bond.dials != 1 || a.dials != 3 {
		t.Fatalf("public dial went bond=%d link=%d, want the bond", bond.dials, a.dials)
	}
}
