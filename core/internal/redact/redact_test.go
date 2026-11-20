package redact

import (
	"strings"
	"testing"
)

func TestURLHidesUserinfoQueryTokensAndOpaquePathSegments(t *testing.T) {
	cases := map[string]string{
		"https://alice:hunter2@example.com/sub":                 "hunter2",
		"https://example.com/api/v1/client/subscribe?token=abc": "abc",
		"https://example.com/link/Zx9QwErTyUiOpAsDfGhJk":        "Zx9QwErTyUiOpAsDfGhJk",
	}
	for in, secret := range cases {
		out := URL(in)
		if strings.Contains(out, secret) {
			t.Errorf("URL(%q) = %q still contains %q", in, out, secret)
		}
		if !strings.Contains(out, "example.com") {
			t.Errorf("URL(%q) = %q lost the host", in, out)
		}
	}
}

func TestTextRedactsURLsQuotedInsideAnErrorMessage(t *testing.T) {
	msg := `Get "https://bob:pw@host.example/sub?token=t0k": dial tcp: timeout`
	out := Text(msg)
	if strings.Contains(out, "pw@") || strings.Contains(out, "t0k") {
		t.Fatalf("Text leaked a secret: %q", out)
	}
	if !strings.Contains(out, "dial tcp") {
		t.Fatalf("Text dropped the message: %q", out)
	}
}

func TestURLStripsUserinfoEvenWhenTheURLDoesNotParse(t *testing.T) {
	out := URL("bad url://user:secret@%zz")
	if strings.Contains(out, "secret") {
		t.Fatalf("URL leaked from an unparsable input: %q", out)
	}
}
