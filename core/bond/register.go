package bond

import "github.com/sagernet/sing-box/include"

// Type is the outbound and inbound type name in sing-box configuration.
// It keeps upstream's name so configurations stay interchangeable with
// singbox-multipath clients and servers of the same protocol version.
const Type = "multipath"

func init() {
	// The fork's hooks (PLAN decision 10): libbox builds a fresh registry per
	// service, so the types must be added to every registry it builds.
	include.RegisterOutboundExtension(RegisterOutbound)
	include.RegisterInboundExtension(RegisterInbound)
}
