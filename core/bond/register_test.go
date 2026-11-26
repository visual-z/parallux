package bond_test

import (
	"strings"
	"testing"

	"github.com/sagernet/sing-box/experimental/libbox"

	_ "github.com/visual-z/parallux/core/bond"
)

func multipathConfig(multipath string) string {
	return `{
  "outbounds": [
    {"type": "direct", "tag": "link-en0", "bind_interface": "en0"},
    {"type": "direct", "tag": "link-en7", "bind_interface": "en7"},
    ` + multipath + `
  ]
}`
}

func TestLibboxAcceptsAMultipathOutboundOverTwoLinks(t *testing.T) {
	err := libbox.CheckConfig(multipathConfig(`{"type": "multipath", "tag": "bond", "outbounds": ["link-en0", "link-en7"],
      "server": "203.0.113.10", "server_port": 39000, "psk": "a-long-random-pre-shared-key-for-tests"}`))
	if err != nil && strings.Contains(err.Error(), "unknown outbound type") {
		t.Fatalf("libbox does not know the multipath type, so core/bond is not registered: %v", err)
	}
	if err != nil {
		t.Fatalf("a multipath outbound over two links should pass CheckConfig: %v", err)
	}
}

func TestLibboxRejectsAMultipathOutboundWithoutAServer(t *testing.T) {
	err := libbox.CheckConfig(multipathConfig(`{"type": "multipath", "tag": "bond", "outbounds": ["link-en0", "link-en7"],
      "server_port": 39000, "psk": "a-long-random-pre-shared-key-for-tests"}`))
	if err == nil || strings.Contains(err.Error(), "unknown outbound type") || !strings.Contains(err.Error(), "server") {
		t.Fatalf("CheckConfig without server = %v, want an error naming server from the multipath outbound", err)
	}
}
