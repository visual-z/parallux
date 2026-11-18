package aggregate_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/sagernet/sing-box/experimental/libbox"
)

// testdata/composed-*.json are what ParalluxKit's ProfileComposer produces
// for the user profile in LinkCompositionTests (its test
// composedFixturesMatchTheGenerator pins that); libbox must accept all three.
func TestComposedFixturesPassLibboxCheckConfig(t *testing.T) {
	for _, mode := range []string{"balance", "failover", "bond"} {
		path := filepath.Join("testdata", "composed-"+mode+".json")
		content, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("read %s: %v", path, err)
		}
		if err := libbox.CheckConfig(string(content)); err != nil {
			t.Fatalf("libbox rejects the composed %s profile: %v", mode, err)
		}
	}
}
