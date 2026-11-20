package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/sagernet/sing-box/experimental/libbox"
)

const testPSK = "server-test-pre-shared-key-0123456789"

func TestTheFlagConfigurationIsAValidMultipathServer(t *testing.T) {
	content, err := Config(ConfigOptions{Listen: "::", Port: 39000, PSK: testPSK, AllowedIPs: []string{"198.51.100.0/24"}})
	if err != nil {
		t.Fatal(err)
	}
	if err := libbox.CheckConfig(string(content)); err != nil {
		t.Fatalf("libbox rejects the generated server configuration: %v\n%s", err, content)
	}
}

func TestAShortPSKOrAZeroPortIsRefused(t *testing.T) {
	if _, err := Config(ConfigOptions{Port: 39000, PSK: "short"}); err == nil {
		t.Fatal("a 5-character psk was accepted")
	}
	if _, err := Config(ConfigOptions{Port: 0, PSK: testPSK}); err == nil {
		t.Fatal("port 0 was accepted")
	}
	if _, err := Config(ConfigOptions{Port: 1, PSK: testPSK}); err != nil {
		t.Fatalf("port 1 was refused: %v", err)
	}
	if _, err := Config(ConfigOptions{Port: 65535, PSK: strings.Repeat("k", minPSKLength)}); err != nil {
		t.Fatalf("a psk of exactly the minimum length was refused: %v", err)
	}
}

func TestCheckModeValidatesWithoutListening(t *testing.T) {
	dir := t.TempDir()
	pskPath := filepath.Join(dir, "psk")
	if err := os.WriteFile(pskPath, []byte(testPSK+"\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := run([]string{"-check", "-port", "39001", "-psk-file", pskPath}); err != nil {
		t.Fatalf("check mode failed: %v", err)
	}
	if err := run([]string{"-check", "-port", "39001"}); err == nil || !strings.Contains(err.Error(), "psk-file") {
		t.Fatalf("missing psk file: err = %v, want it to name -psk-file", err)
	}
}
