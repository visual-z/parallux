package pxbridge

import (
	"strings"
	"testing"
)

func TestRedactTextRemovesSubscriptionSecrets(t *testing.T) {
	const canaryToken = "Zq3x0b9Ck2mVv7yQ1nH8sJt4wE6r"
	const canaryPassword = "hunter2-canary"
	logs := strings.Join([]string{
		"INFO update https://sub.example.com/api/v1/client/subscribe?token=" + canaryToken,
		"ERROR fetch https://alice:" + canaryPassword + "@sub.example.com/link",
		"DEBUG https://example.com/" + canaryToken + "/config.json",
		"INFO inbound/tun: connection to example.com:443",
	}, "\n")
	got := RedactText(logs)
	for _, secret := range []string{canaryToken, canaryPassword} {
		if strings.Contains(got, secret) {
			t.Fatalf("exported logs still contain %q:\n%s", secret, got)
		}
	}
	if !strings.Contains(got, "connection to example.com:443") {
		t.Fatalf("redaction removed an ordinary line:\n%s", got)
	}
}
