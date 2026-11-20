package pxbridge

import (
	"os"
	"testing"

	"github.com/sagernet/sing-box/experimental/libbox"
)

// testdata/probe-profile.json is the shape LinkProbeProfile.make produces for
// en0 and en7 (ParalluxKit test theProbeProfileHasOneBoundDirectPerInterface
// pins the same structure). libbox must accept it, or the diagnostics page's
// sing-box arm would fail before it measures anything.
func TestTheLinkProbeProfileShapePassesLibboxCheckConfig(t *testing.T) {
	content, err := os.ReadFile("testdata/probe-profile.json")
	if err != nil {
		t.Fatalf("read the probe profile fixture: %v", err)
	}
	if err := libbox.CheckConfig(string(content)); err != nil {
		t.Fatalf("libbox rejects the probe profile: %v", err)
	}
}
