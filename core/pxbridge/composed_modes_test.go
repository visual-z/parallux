package pxbridge

import (
	"os"
	"strings"
	"testing"

	"github.com/sagernet/sing-box/experimental/libbox"
)

// The fixture ParalluxKit produces for a profile without modes (RouteModes
// adds the two mode rules, then ProfileComposer adds the links; pinned by
// composedModesFixtureMatchesTheGenerator). libbox must accept the logical
// rule with an inverted ip_is_private inside it, and the aggregate that
// stands in for the direct outbound the Direct rule names.
func TestTheComposedModesProfilePassesLibboxCheckConfig(t *testing.T) {
	content, err := os.ReadFile("../aggregate/testdata/composed-modes.json")
	if err != nil {
		t.Fatalf("read the composed modes fixture: %v", err)
	}
	if err := libbox.CheckConfig(string(content)); err != nil {
		t.Fatalf("libbox rejects the composed modes profile: %v", err)
	}
	for _, want := range []string{`"clash_mode" : "Direct"`, `"clash_mode" : "Global"`, `"invert" : true`, `"type" : "aggregate"`} {
		if !strings.Contains(string(content), want) {
			t.Fatalf("the composed modes profile lacks %s", want)
		}
	}
}
