// Package pxbridge is the Go surface the Swift side links against.
//
// It is bound with gomobile together with sing-box's experimental/libbox into
// one Libbox.xcframework (scripts/build-core.sh). libbox already exposes the
// sing-box service and its command server; this package only carries what
// Parallux adds on top (aggregation, per-link stats). Every exported name here
// is an ABI the Swift code depends on, so keep the surface small and typed
// with gomobile-compatible types only (no context, no func values, no maps).
package pxbridge

import (
	C "github.com/sagernet/sing-box/constant"
)

// CoreVersion is the Parallux core version. Release builds override it with
// -ldflags "-X github.com/visual-z/parallux/core/pxbridge.CoreVersion=…".
var CoreVersion = "0.0.0-dev"

// Version reports the Parallux core version and the sing-box version it
// embeds, e.g. "0.0.0-dev (sing-box 1.14.4)". The app shows it in Settings ›
// Core, and bug reports quote it verbatim.
func Version() string {
	return CoreVersion + " (sing-box " + C.Version + ")"
}
