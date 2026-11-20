package main

import (
	"context"
	"net"
	"net/netip"
	"time"

	M "github.com/sagernet/sing/common/metadata"
)

// Delivery to this machine itself (同机节点, PLAN decision 25). stubs:
// feat-node-hosted-aggregation

// selfType is the outbound type of the configuration's self delivery.
const selfType = "parallux-self"

// stubs
const (
	maxSelf              = 16
	localDeliveryTimeout = time.Second
)

// lookupSelf resolves a self name; tests replace it.
var lookupSelf = func(ctx context.Context, host string) ([]netip.Addr, error) {
	return net.DefaultResolver.LookupNetIP(ctx, "ip", host)
}

// selfDelivery dials destinations that name this machine.
type selfDelivery struct {
	listenPort uint16
	target     netip.Addr
	dial       func(ctx context.Context, network, address string) (net.Conn, error)
	source     func(destination netip.Addr) (netip.Addr, bool)
}

// DialContext. stub
func (s *selfDelivery) DialContext(ctx context.Context, network string, destination M.Socksaddr) (net.Conn, error) {
	return s.dial(ctx, network, destination.String())
}

// expandSelf adds the addresses the names in self resolve to. stub
func expandSelf(ctx context.Context, self []string, lookup func(ctx context.Context, host string) ([]netip.Addr, error)) []string {
	return self
}
