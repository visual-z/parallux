package pxbridge

import (
	"strings"
	"testing"

	C "github.com/sagernet/sing-box/constant"
)

func TestVersionNamesTheCoreAndTheEmbeddedSingBox(t *testing.T) {
	got := Version()
	if !strings.HasPrefix(got, CoreVersion+" ") {
		t.Fatalf("Version() = %q, want it to start with the core version %q", got, CoreVersion)
	}
	if !strings.Contains(got, "sing-box "+C.Version) {
		t.Fatalf("Version() = %q, want it to name sing-box %s", got, C.Version)
	}
}
