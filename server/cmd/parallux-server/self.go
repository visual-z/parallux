package main

import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/netip"
	"regexp"
	"slices"
	"strings"
	"time"

	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/adapter/outbound"
	C "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/log"
	E "github.com/sagernet/sing/common/exceptions"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
)

// Self delivery (本机投递, PLAN decision 25): how the aggregation server
// reaches a proxy node that lives on its own machine (同机节点).
//
// The client asks for the node by the address the outside world uses. On a
// cloud that maps the public address onto a private one, dialing that
// address from inside may or may not come back, and when it does not the
// client cannot tell: its bonded dial has already succeeded and it never
// falls back to its links (docs/research/node-hosted-aggregation-2026-11-20.md).
// So connections to this machine's own addresses are tried locally first.

// selfType is the outbound type of the configuration's self delivery.
const selfType = "parallux-self"

// selfTag is its tag; route rules point at it.
const selfTag = "self"

const (
	// maxSelf bounds the identities of one machine: a few addresses and a
	// name or two, including what the names resolve to. Why 16: each is a
	// route rule entry matched per connection, and more than a handful is a
	// misconfiguration (a name behind a large pool). Assumed value.
	maxSelf = 16
	// localDeliveryTimeout bounds the local attempt. Why 1 s: a local
	// connection is accepted or refused within milliseconds; only a firewall
	// that drops packets to the machine's own address makes it hang, and
	// then every connection would wait this long before the address as
	// given is tried. Assumed value.
	localDeliveryTimeout = time.Second
	// selfLookupTimeout bounds resolving the names in -self at startup, so
	// a dead resolver delays the start by this much and no more. Assumed.
	selfLookupTimeout = 3 * time.Second
)

// lookupSelf resolves a self name; tests replace it.
var lookupSelf = func(ctx context.Context, host string) ([]netip.Addr, error) {
	return net.DefaultResolver.LookupNetIP(ctx, "ip", host)
}

// selfDelivery dials destinations that name this machine.
type selfDelivery struct {
	// listenPort is the multipath listener's port: a connection to this
	// machine on that port would be the server talking to itself.
	listenPort uint16
	// target, when set, is tried first instead of the source address.
	target netip.Addr
	dial   func(ctx context.Context, network, address string) (net.Conn, error)
	// source is the address this machine would send from to reach
	// destination; false when it cannot tell.
	source func(destination netip.Addr) (netip.Addr, bool)
}

// DialContext tries the machine's own address on the destination's port,
// and the destination as given when nothing answers there. The fallback is
// what makes generous matching safe: an address that turns out to be a
// forwarder in front of this machine, or a port nothing local listens on,
// costs one refused local connection and then behaves as before.
func (s *selfDelivery) DialContext(ctx context.Context, network string, destination M.Socksaddr) (net.Conn, error) {
	if destination.Port == s.listenPort {
		return nil, E.New("refusing to dial this server's own listener at ", destination)
	}
	if local, ok := s.local(destination); ok {
		attempt, cancel := context.WithTimeout(ctx, localDeliveryTimeout)
		conn, err := s.dial(attempt, network, netip.AddrPortFrom(local, destination.Port).String())
		cancel()
		if err == nil {
			return conn, nil
		}
		// The caller giving up ends it; a refusal or the bound moves on.
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
	}
	return s.dial(ctx, network, destination.String())
}

// local is the address to try first, if there is one that differs from the
// destination itself.
//
// It is the address on the network interface, not 127.0.0.1: the cloud's
// address mapping delivers outside connections to that address, so what
// answers there is what the outside can reach anyway. Loopback would open
// loopback-only services (panels, APIs) to whoever holds the key.
func (s *selfDelivery) local(destination M.Socksaddr) (netip.Addr, bool) {
	if s.target.IsValid() {
		return s.target, !destination.IsIP() || destination.Addr.Unmap() != s.target
	}
	if !destination.IsIP() {
		// The router resolves names before this outbound sees them; one
		// that arrives unresolved has no address to find a source for.
		return netip.Addr{}, false
	}
	source, ok := s.source(destination.Addr)
	if !ok || source == destination.Addr.Unmap() {
		// The public address is on an interface: the kernel delivers it.
		return netip.Addr{}, false
	}
	return source, true
}

// sourceAddress asks the kernel which address it would send from to reach
// destination. Connecting a UDP socket sends nothing.
func sourceAddress(destination netip.Addr) (netip.Addr, bool) {
	conn, err := net.Dial("udp", netip.AddrPortFrom(destination, 9).String())
	if err != nil {
		return netip.Addr{}, false
	}
	defer conn.Close()
	local, ok := conn.LocalAddr().(*net.UDPAddr)
	if !ok {
		return netip.Addr{}, false
	}
	address, ok := netip.AddrFromSlice(local.IP)
	return address.Unmap(), ok
}

// selfOptions is the JSON shape of the self-delivery outbound.
type selfOptions struct {
	ListenPort uint16 `json:"listen_port"`
	Target     string `json:"target,omitempty"`
}

// selfOutbound is selfDelivery as a sing-box outbound. TCP only: the
// multipath inbound hands the router nothing else.
type selfOutbound struct {
	outbound.Adapter
	logger   log.ContextLogger
	delivery *selfDelivery
}

func init() {
	include.RegisterOutboundExtension(func(registry *outbound.Registry) {
		outbound.Register[selfOptions](registry, selfType, newSelfOutbound)
	})
}

func newSelfOutbound(ctx context.Context, router adapter.Router, logger log.ContextLogger, tag string, options selfOptions) (adapter.Outbound, error) {
	var target netip.Addr
	if options.Target != "" {
		parsed, err := netip.ParseAddr(options.Target)
		if err != nil {
			return nil, E.New("self delivery target ", options.Target, " is not an address")
		}
		target = parsed.Unmap()
	}
	// The connect timeout sing-box's own dialers use; without one a
	// blackholed address would hold the connection for the kernel's default.
	dialer := &net.Dialer{Timeout: C.TCPConnectTimeout}
	return &selfOutbound{
		Adapter: outbound.NewAdapter(selfType, tag, []string{N.NetworkTCP}, nil),
		logger:  logger,
		delivery: &selfDelivery{
			listenPort: options.ListenPort,
			target:     target,
			dial:       dialer.DialContext,
			source:     sourceAddress,
		},
	}, nil
}

func (o *selfOutbound) DialContext(ctx context.Context, network string, destination M.Socksaddr) (net.Conn, error) {
	o.logger.InfoContext(ctx, "connection to this machine at ", destination)
	return o.delivery.DialContext(ctx, network, destination)
}

func (o *selfOutbound) ListenPacket(ctx context.Context, destination M.Socksaddr) (net.PacketConn, error) {
	return nil, errors.New("self delivery carries TCP only")
}

// hostName matches a DNS host name in lower case without a trailing dot.
var hostName = regexp.MustCompile(`^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$`)

// parseSelf splits the -self entries into addresses and names, normalised
// and without duplicates. An entry with a port, a scheme or anything else
// that is neither is an error naming it: a silently ignored entry would
// leave the node unreachable with nothing to show why.
func parseSelf(entries []string) (addresses []netip.Addr, names []string, err error) {
	if len(entries) > maxSelf {
		return nil, nil, fmt.Errorf("%d self entries, want at most %d", len(entries), maxSelf)
	}
	for _, entry := range entries {
		if address, parseErr := netip.ParseAddr(entry); parseErr == nil {
			address = address.Unmap()
			if !slices.Contains(addresses, address) {
				addresses = append(addresses, address)
			}
			continue
		}
		name := strings.ToLower(strings.TrimSuffix(entry, "."))
		labels := strings.Split(name, ".")
		// An all-digit last label is a mistyped address, not a name.
		if len(name) > 253 || !hostName.MatchString(name) || strings.Trim(labels[len(labels)-1], "0123456789") == "" {
			return nil, nil, fmt.Errorf("self entry %q is neither an address nor a host name", entry)
		}
		if !slices.Contains(names, name) {
			names = append(names, name)
		}
	}
	return addresses, names, nil
}

// expandSelf appends the addresses the names in self resolve to, so a
// client that sends the address instead of the name (a node with its own
// resolver does) is recognised too. Names stay, known addresses are not
// repeated, a failed lookup changes nothing, and the result never exceeds
// maxSelf.
func expandSelf(ctx context.Context, self []string, lookup func(ctx context.Context, host string) ([]netip.Addr, error)) []string {
	expanded := slices.Clone(self)
	known := map[netip.Addr]bool{}
	for _, entry := range self {
		if address, err := netip.ParseAddr(entry); err == nil {
			known[address.Unmap()] = true
		}
	}
	for _, entry := range self {
		if _, err := netip.ParseAddr(entry); err == nil {
			continue
		}
		addresses, err := lookup(ctx, entry)
		if err != nil {
			continue
		}
		for _, address := range addresses {
			address = address.Unmap()
			if known[address] {
				continue
			}
			if len(expanded) >= maxSelf {
				return expanded
			}
			known[address] = true
			expanded = append(expanded, address.String())
		}
	}
	return expanded
}
