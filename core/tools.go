//go:build tools

// Package core pins modules that are built by scripts rather than imported by
// Go code, so go.mod and go.sum record their exact versions:
//
//   - experimental/libbox is bound into Libbox.xcframework next to pxbridge
//     (scripts/build-core.sh); the Swift side drives sing-box through it.
//   - sagernet/gomobile is the gomobile fork sing-box's own Apple build uses
//     (sing-box cmd/internal/build_libbox); upstream gomobile lacks its flags.
package core

import (
	_ "github.com/sagernet/gomobile/cmd/gobind"
	_ "github.com/sagernet/gomobile/cmd/gomobile"
	_ "github.com/sagernet/sing-box/experimental/libbox"
)
