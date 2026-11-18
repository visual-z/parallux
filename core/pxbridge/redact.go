package pxbridge

// RedactText strips credentials from text before it leaves the Mac (log
// export, bug reports). It is core/internal/redact.Text, exposed so the app
// uses the one implementation that has the tests.
func RedactText(s string) string {
	return s
}
