package pxbridge

import (
	"os"
	"testing"

	"github.com/sagernet/sing-box/experimental/libbox"
)

// The app ships this file for the first connection (apple/Parallux/Tunnel/
// SampleProfile.swift); the extension hands it to libbox unchanged, so
// CheckConfig here is the same validation the extension would hit.
func TestTheBundledSampleProfilePassesLibboxCheckConfig(t *testing.T) {
	content, err := os.ReadFile("../../apple/Parallux/Resources/sample-profile.json")
	if err != nil {
		t.Fatalf("read the bundled sample profile: %v", err)
	}
	if err := libbox.CheckConfig(string(content)); err != nil {
		t.Fatalf("the bundled sample profile is rejected by libbox: %v", err)
	}
}
