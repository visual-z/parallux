package pxbridge

import "github.com/visual-z/parallux/core/internal/redact"

// RedactText strips credentials from text before it leaves the Mac (log
// export, bug reports). It is core/internal/redact.Text, exposed so the app
// uses the one implementation that has the tests.
func RedactText(s string) string {
	return redact.Text(s)
}
