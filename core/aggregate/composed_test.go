package aggregate_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/sagernet/sing-box/experimental/libbox"
)

// testdata/composed-*.json are what ParalluxKit's ProfileComposer produces
// for the user profile in LinkCompositionTests (its test
// composedFixturesMatchTheGenerator pins that); libbox must accept them.
func TestComposedFixturesPassLibboxCheckConfig(t *testing.T) {
	for _, mode := range []string{"balance", "failover"} {
		checkFixture(t, mode)
	}
}

// The bond fixture also needs the multipath type (core/bond);
// pxbridge links both, so the check lives where both are registered.
func checkFixture(t *testing.T, mode string) {
	t.Helper()
	path := filepath.Join("testdata", "composed-"+mode+".json")
	content, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	if err := libbox.CheckConfig(string(content)); err != nil {
		t.Fatalf("libbox rejects the composed %s profile: %v", mode, err)
	}
	if !strings.Contains(string(content), `"type" : "aggregate"`) {
		t.Fatalf("the composed %s profile has no aggregate outbound", mode)
	}
}
