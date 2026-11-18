package pxbridge

// Linking pxbridge into Libbox.xcframework also links Parallux's protocol
// types: their init functions register them with the sing-box fork's hooks,
// and libbox in the same binary then accepts them in every configuration.
import (
	_ "github.com/visual-z/parallux/core/aggregate"
)
