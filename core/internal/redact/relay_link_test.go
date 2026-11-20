package redact

import (
	"strings"
	"testing"
)

// A relay import link (docs/research/relay-link.md) carries the relay key in
// its query; an error message or a log line that quotes the link must not.
func TestARelayImportLinkLosesItsKey(t *testing.T) {
	const key = "MDEyMzQ1Njc4OWFiY2RlZg%3D%3D" // "0123456789abcdef", not a real key
	link := "parallux://relay?v=1&host=10.0.0.21&port=39100&method=2022-blake3-aes-128-gcm&key=" + key + "#worker-1"
	for name, out := range map[string]string{
		"URL":  URL(link),
		"Text": Text(`add relay "` + link + `": line 3 is not a relay link`),
	} {
		if strings.Contains(out, "MDEyMzQ1") {
			t.Errorf("%s leaked the relay key: %q", name, out)
		}
		if !strings.Contains(out, "10.0.0.21") {
			t.Errorf("%s dropped the host: %q", name, out)
		}
	}
	// The aggregation server's link is the same kind of secret.
	server := "parallux://aggregation-server?v=1&host=203.0.113.24&port=39000&psk=Zq3x0b9Ck2mVv7yQ1nH8sJt4wE6rU5aPxLdFgTiO0Bc#vps"
	if out := Text("paste failed: " + server); strings.Contains(out, "Zq3x0b9C") || !strings.Contains(out, "203.0.113.24") {
		t.Errorf("Text leaked the pre-shared key or dropped the host: %q", out)
	}
}
