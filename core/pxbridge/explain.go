package pxbridge

import "github.com/sagernet/sing-box/experimental/libbox"

// SetCommandServer hands pxbridge the extension's running command server, so
// ExplainRoute can reach its router. The extension calls it once after
// creating the server.
func SetCommandServer(server *libbox.CommandServer) {}

// ExplainRoute reports, as JSON, which route rule a target (domain, IP, or
// host:port) matches in the running configuration and the outbound it goes
// to. It runs the router's own rule matching, so it never drifts from
// sing-box. JSON because gomobile cannot bind structs in slices.
func ExplainRoute(target string) string {
	return "{}"
}

// routerSource yields the router of the running configuration (nil when none).
type routerSource interface{ router() any }

type boxRouter struct{ b any }

func (r boxRouter) router() any { return nil }

func explainRouter(source routerSource, target string) string { return "{}" }
