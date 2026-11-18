// Package redact strips credentials from strings that may reach logs, error
// messages or the UI. Subscription URLs routinely carry tokens in userinfo,
// the query string or the path; a log line or a crash report is enough to
// leak an account.
package redact

import (
	"net/url"
	"regexp"
	"strings"
)

// Placeholder replaces every secret, so redacted output still shows where
// one was.
const Placeholder = "***"

// sensitiveKeys are query parameters that subscription services use for
// credentials. Matching is case-insensitive.
var sensitiveKeys = map[string]bool{
	"token": true, "key": true, "secret": true, "password": true, "passwd": true,
	"pass": true, "auth": true, "access_token": true, "apikey": true, "api_key": true,
	"sig": true, "signature": true, "uuid": true, "sub": true,
}

// longOpaque matches path segments that look like tokens: 16+ characters of
// URL-safe base64 or hex. Airport subscription URLs put the token there.
var longOpaque = regexp.MustCompile(`^[A-Za-z0-9_\-]{16,}$`)

// URL redacts userinfo, sensitive query values and token-like path
// segments. Input that does not parse as a URL is returned with any
// "user:pass@" prefix removed, so a malformed URL cannot smuggle a password.
func URL(raw string) string {
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" {
		return userinfo.ReplaceAllString(raw, "${1}"+Placeholder+"@")
	}
	if u.User != nil {
		u.User = url.User(Placeholder)
	}
	if u.RawQuery != "" {
		q := u.Query()
		for k := range q {
			if sensitiveKeys[strings.ToLower(k)] {
				q.Set(k, Placeholder)
			}
		}
		u.RawQuery = q.Encode()
	}
	segments := strings.Split(u.Path, "/")
	for i, s := range segments {
		if longOpaque.MatchString(s) {
			segments[i] = Placeholder
		}
	}
	u.Path = strings.Join(segments, "/")
	u.RawPath = ""
	return strings.ReplaceAll(u.String(), url.QueryEscape(Placeholder), Placeholder)
}

var userinfo = regexp.MustCompile(`(^|//)[^/@\s]+@`)

// Text redacts every http(s) URL inside free text, such as an error message
// that quotes the URL it failed on.
func Text(s string) string {
	return urlInText.ReplaceAllStringFunc(s, URL)
}

var urlInText = regexp.MustCompile(`https?://[^\s"'<>]+`)
