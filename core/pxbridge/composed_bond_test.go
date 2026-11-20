package pxbridge

import (
	"os"
	"testing"

	"github.com/sagernet/sing-box/experimental/libbox"
)

// The 叠加 fixture ParalluxKit's ProfileComposer produces (core/aggregate
// testdata, pinned by composedFixturesMatchTheGenerator) needs both the
// aggregate and the multipath types; pxbridge links both, as the framework does.
func TestTheComposedBondProfilePassesLibboxCheckConfig(t *testing.T) {
	content, err := os.ReadFile("../aggregate/testdata/composed-bond.json")
	if err != nil {
		t.Fatalf("read the composed bond fixture: %v", err)
	}
	if err := libbox.CheckConfig(string(content)); err != nil {
		t.Fatalf("libbox rejects the composed bond profile: %v", err)
	}
}
