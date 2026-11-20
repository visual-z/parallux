package pxbridge

import (
	"os"
	"strings"
	"testing"

	"github.com/sagernet/sing-box/experimental/libbox"
)

// The relay fixture ParalluxKit's ProfileComposer produces (core/aggregate
// testdata, pinned by composedRelayFixtureMatchesTheGenerator): two physical
// links and two relay links. libbox must accept the aggregate's `relays`
// field and a shadowsocks outbound that detours to a link outbound.
func TestTheComposedRelayProfilePassesLibboxCheckConfig(t *testing.T) {
	content, err := os.ReadFile("../aggregate/testdata/composed-relay.json")
	if err != nil {
		t.Fatalf("read the composed relay fixture: %v", err)
	}
	if err := libbox.CheckConfig(string(content)); err != nil {
		t.Fatalf("libbox rejects the composed relay profile: %v", err)
	}
	for _, want := range []string{`"relays" : [`, `"type" : "shadowsocks"`, `"detour" : "link-en7"`} {
		if !strings.Contains(string(content), want) {
			t.Fatalf("the composed relay profile lacks %s", want)
		}
	}
}
