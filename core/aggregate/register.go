package aggregate

import (
	"context"
	"io"
	"net"
	"slices"
	"sync/atomic"

	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/adapter/outbound"
	"github.com/sagernet/sing-box/common/interrupt"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/log"
	E "github.com/sagernet/sing/common/exceptions"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
	"github.com/sagernet/sing/service"
)

// Type is the outbound type name in sing-box configuration.
const Type = "aggregate"

// Mode values; they match ParalluxKit's AggregationMode raw values so the UI
// preset can write them verbatim.
const (
	ModeBalance  = "balance"
	ModeBond     = "bond"
	ModeFailover = "failover"
)

// Options is the JSON shape of an aggregate outbound.
type Options struct {
	// Mode is balance, bond or failover.
	Mode string `json:"mode"`
	// Links are the tags of the link outbounds, in priority order: failover
	// uses the first one that dials, balance rotates over all of them.
	Links []string `json:"links"`
}

func init() {
	// The fork's hook (PLAN decision 10): libbox builds a fresh registry per
	// service, so the type must be added to every registry it builds.
	include.RegisterOutboundExtension(func(registry *outbound.Registry) {
		outbound.Register[Options](registry, Type, New)
	})
}

var (
	_ adapter.OutboundGroup = (*Outbound)(nil)
	_ adapter.Referrer      = (*Outbound)(nil)
)

// Outbound spreads connections over its link outbounds.
//
// This is the M1 foundation: options, validation, and plain per-connection
// selection. Link health, per-link statistics and the bond mode arrive in M3/M4.
type Outbound struct {
	outbound.Adapter
	manager adapter.OutboundManager
	logger  log.ContextLogger
	mode    string
	tags    []string
	links   []adapter.Outbound
	next    atomic.Uint64 // balance: index of the link that takes the next connection
	// interrupts closes the connections attached through AttachConnection
	// when the group changes its links (M3 health checks will use it).
	interrupts *interrupt.Group
}

// New builds an aggregate outbound. Link tags are resolved in Start, because
// sing-box creates outbounds before any of them can be looked up.
func New(ctx context.Context, router adapter.Router, logger log.ContextLogger, tag string, options Options) (adapter.Outbound, error) {
	switch options.Mode {
	case ModeBalance, ModeFailover:
	case ModeBond:
		return nil, E.New("aggregate: mode bond is not available yet (milestone M4)")
	default:
		return nil, E.New("aggregate: unknown mode ", options.Mode, ", want balance, bond or failover")
	}
	if len(options.Links) == 0 {
		return nil, E.New("aggregate: links is empty, want at least one link outbound tag")
	}
	for i, link := range options.Links {
		if slices.Contains(options.Links[:i], link) {
			return nil, E.New("aggregate: duplicate link ", link)
		}
	}
	return &Outbound{
		Adapter:    outbound.NewAdapter(Type, tag, []string{N.NetworkTCP, N.NetworkUDP}, options.Links),
		manager:    service.FromContext[adapter.OutboundManager](ctx),
		logger:     logger,
		mode:       options.Mode,
		tags:       options.Links,
		interrupts: interrupt.NewGroup(),
	}, nil
}

func (o *Outbound) Start(stage adapter.StartStage, _ *adapter.Scope) error {
	if stage != adapter.StartStateStart {
		return nil
	}
	o.links = make([]adapter.Outbound, 0, len(o.tags))
	for _, tag := range o.tags {
		link, loaded := o.manager.Outbound(tag)
		if !loaded {
			return E.New("aggregate: link outbound not found: ", tag)
		}
		o.links = append(o.links, link)
	}
	return nil
}

// All implements adapter.OutboundGroup so the UI lists the links.
func (o *Outbound) All() []string { return o.tags }

// Selected reports the link the next connection would try first.
func (o *Outbound) Selected(string) adapter.Outbound {
	if len(o.links) == 0 {
		return nil
	}
	return o.links[o.firstIndex(false)]
}

// AttachConnection implements adapter.OutboundGroup.
func (o *Outbound) AttachConnection(closer io.Closer) func() {
	return o.interrupts.Add(closer, true)
}

// References implements adapter.Referrer.
func (o *Outbound) References() []string { return o.tags }

func (o *Outbound) DialContext(ctx context.Context, network string, destination M.Socksaddr) (net.Conn, error) {
	var lastErr error
	for _, link := range o.order() {
		conn, err := link.DialContext(ctx, network, destination)
		if err == nil {
			return conn, nil
		}
		lastErr = err
		o.logger.DebugContext(ctx, "link ", link.Tag(), " failed: ", err)
	}
	return nil, E.Cause(lastErr, "aggregate: every link failed")
}

func (o *Outbound) ListenPacket(ctx context.Context, destination M.Socksaddr) (net.PacketConn, error) {
	var lastErr error
	for _, link := range o.order() {
		conn, err := link.ListenPacket(ctx, destination)
		if err == nil {
			return conn, nil
		}
		lastErr = err
		o.logger.DebugContext(ctx, "link ", link.Tag(), " failed: ", err)
	}
	return nil, E.Cause(lastErr, "aggregate: every link failed")
}

// order returns the links in the order one connection should try them: the
// configured order for failover, and for balance the same ring started at the
// next link in rotation, so a failing link only costs a retry.
func (o *Outbound) order() []adapter.Outbound {
	start := o.firstIndex(true)
	ordered := make([]adapter.Outbound, 0, len(o.links))
	for i := range o.links {
		ordered = append(ordered, o.links[(start+i)%len(o.links)])
	}
	return ordered
}

func (o *Outbound) firstIndex(advance bool) int {
	if o.mode != ModeBalance || len(o.links) == 0 {
		return 0
	}
	if advance {
		return int((o.next.Add(1) - 1) % uint64(len(o.links)))
	}
	return int(o.next.Load() % uint64(len(o.links)))
}
