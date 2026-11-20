package aggregate

import (
	"context"
	"net"
	"slices"
	"sync"
	"sync/atomic"

	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/adapter/outbound"
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
	// uses the first healthy one, balance rotates over the healthy ones.
	Links []string `json:"links"`
	// Backup lists links used only when no other link is healthy
	// (design: 「仅备用」). Must be a subset of Links.
	Backup []string `json:"backup,omitempty"`
	// Bond is the tag of the outbound that splits one connection over the
	// links (a multipath outbound, PLAN decision 17). Required in bond mode;
	// when it fails, connections fall back to the links in failover order.
	Bond string `json:"bond,omitempty"`
	// BondBypass lists hosts never sent through the bond (the aggregation
	// server itself), besides local destinations (feat-bond-direct).
	BondBypass []string `json:"bond_bypass,omitempty"`
	// ProbeTargets override the health-check destinations ("host:port").
	ProbeTargets []string `json:"probe_targets,omitempty"`
}

func init() {
	// The fork's hook (PLAN decision 10): libbox builds a fresh registry per
	// service, so the type must be added to every registry it builds.
	include.RegisterOutboundExtension(func(registry *outbound.Registry) {
		outbound.Register[Options](registry, Type, New)
	})
}

// Outbound is deliberately not an adapter.OutboundGroup: sing-box's router
// expands groups through Selected() and dials the last outbound itself
// (route/route.go resolveOutbound), which would skip this outbound's
// DialContext and with it rotation, failover retries and per-link counters
// (docs/tasks/fix-aggregate-routing.md).
var _ adapter.Referrer = (*Outbound)(nil)

// Outbound spreads connections over its link outbounds (PLAN decision 13).
type Outbound struct {
	outbound.Adapter
	manager adapter.OutboundManager
	logger  log.ContextLogger
	mode    string
	tags    []string
	backup  []bool
	bondTag string
	// bondBypass: hosts kept off the bond besides local ones (bondEligible).
	bondBypass []string
	targets    []M.Socksaddr

	links    []adapter.Outbound
	bond     adapter.Outbound
	health   []*linkHealth
	counters []*linkCounters
	next     atomic.Uint64 // balance: rotation cursor
	cancel   context.CancelFunc
	probes   sync.WaitGroup
	// disableProbes is for tests that drive health directly.
	disableProbes bool
}

// New builds an aggregate outbound. Link tags are resolved in Start, because
// sing-box creates outbounds before any of them can be looked up.
func New(ctx context.Context, router adapter.Router, logger log.ContextLogger, tag string, options Options) (adapter.Outbound, error) {
	return newOutbound(service.FromContext[adapter.OutboundManager](ctx), logger, tag, options)
}

func newOutbound(manager adapter.OutboundManager, logger log.ContextLogger, tag string, options Options) (*Outbound, error) {
	switch options.Mode {
	case ModeBalance, ModeFailover:
	case ModeBond:
		if options.Bond == "" {
			return nil, E.New("aggregate: mode bond needs `bond`, the tag of a multipath outbound")
		}
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
	for _, link := range options.Backup {
		if !slices.Contains(options.Links, link) {
			return nil, E.New("aggregate: backup link ", link, " is not in links")
		}
	}
	backup := make([]bool, len(options.Links))
	for i, link := range options.Links {
		backup[i] = slices.Contains(options.Backup, link)
	}
	targets := defaultProbeTargets
	if len(options.ProbeTargets) > 0 {
		targets = nil
		for _, target := range options.ProbeTargets {
			address := M.ParseSocksaddr(target)
			if !address.IsValid() || address.Port == 0 {
				return nil, E.New("aggregate: probe target ", target, " is not host:port")
			}
			targets = append(targets, address)
		}
	}
	dependencies := slices.Clone(options.Links)
	if options.Bond != "" {
		dependencies = append(dependencies, options.Bond)
	}
	return &Outbound{
		Adapter:    outbound.NewAdapter(Type, tag, []string{N.NetworkTCP, N.NetworkUDP}, dependencies),
		manager:    manager,
		logger:     logger,
		mode:       options.Mode,
		tags:       options.Links,
		backup:     backup,
		bondTag:    options.Bond,
		bondBypass: slices.Clone(options.BondBypass),
		targets:    targets,
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
	if o.bondTag != "" {
		bond, loaded := o.manager.Outbound(o.bondTag)
		if !loaded {
			return E.New("aggregate: bond outbound not found: ", o.bondTag)
		}
		o.bond = bond
	}
	o.health = make([]*linkHealth, len(o.links))
	o.counters = make([]*linkCounters, len(o.links))
	ctx, cancel := context.WithCancel(context.Background())
	o.cancel = cancel
	for i, link := range o.links {
		o.health[i] = &linkHealth{}
		// Optimistic until the first probe says otherwise, so the first
		// connections after start do not wait for a probe round.
		o.health[i].healthy.Store(true)
		o.counters[i] = &linkCounters{}
		if o.disableProbes {
			continue
		}
		o.probes.Add(1)
		go func(link adapter.Outbound, health *linkHealth) {
			defer o.probes.Done()
			probeLoop(ctx, link, o.targets, health)
		}(link, o.health[i])
	}
	registry.Store(o.Tag(), o)
	return nil
}

func (o *Outbound) Close() error {
	registry.Delete(o.Tag())
	if o.cancel != nil {
		o.cancel()
		o.probes.Wait()
	}
	return nil
}

// References implements adapter.Referrer.
func (o *Outbound) References() []string {
	if o.bondTag != "" {
		return append(slices.Clone(o.tags), o.bondTag)
	}
	return o.tags
}

func (o *Outbound) DialContext(ctx context.Context, network string, destination M.Socksaddr) (net.Conn, error) {
	if o.bond != nil && network == N.NetworkTCP && bondEligible(destination, o.bondBypass) {
		conn, err := o.bond.DialContext(ctx, network, destination)
		if err == nil {
			return conn, nil
		}
		o.logger.DebugContext(ctx, "bond ", o.bondTag, " failed, falling back to the links: ", err)
	}
	var lastErr error
	for _, index := range o.order(true) {
		conn, err := o.links[index].DialContext(ctx, network, destination)
		if err == nil {
			return newCountedConn(conn, o.counters[index]), nil
		}
		lastErr = err
		retry, down := dialFailure(err)
		if down {
			o.markFailed(index)
		}
		o.logger.DebugContext(ctx, "link ", o.tags[index], " failed: ", err)
		if !retry {
			return nil, err
		}
	}
	return nil, everyLinkFailed(lastErr)
}

// everyLinkFailed wraps the last link's error; with no link tried there is none.
func everyLinkFailed(last error) error {
	if last == nil {
		return E.New("aggregate: no link to try")
	}
	return E.Cause(last, "aggregate: every link failed")
}

func (o *Outbound) ListenPacket(ctx context.Context, destination M.Socksaddr) (net.PacketConn, error) {
	var lastErr error
	for _, index := range o.order(true) {
		conn, err := o.links[index].ListenPacket(ctx, destination)
		if err == nil {
			return conn, nil
		}
		lastErr = err
		retry, down := dialFailure(err)
		if down {
			o.markFailed(index)
		}
		o.logger.DebugContext(ctx, "link ", o.tags[index], " failed: ", err)
		if !retry {
			return nil, err
		}
	}
	return nil, everyLinkFailed(lastErr)
}

// A link-level dial failure (dialFailure) is stronger evidence than a probe:
// mark it at once, and let the prober bring it back after recoverAfter
// successes. The prober's streak restarts so one lucky tick cannot undo it.
func (o *Outbound) markFailed(index int) {
	if index < len(o.health) && o.health[index] != nil {
		o.health[index].healthy.Store(false)
		o.health[index].dialFailed.Store(true)
	}
}

func (o *Outbound) healthSnapshot() []bool {
	healthy := make([]bool, len(o.links))
	for i := range healthy {
		healthy[i] = i >= len(o.health) || o.health[i] == nil || o.health[i].healthy.Load()
	}
	return healthy
}

func (o *Outbound) order(advance bool) []int {
	if len(o.links) == 0 {
		return nil
	}
	var cursor uint64
	if o.mode == ModeBalance {
		if advance {
			cursor = o.next.Add(1) - 1
		} else {
			cursor = o.next.Load()
		}
	}
	order := linkOrder(o.mode, o.healthSnapshot(), o.backup, cursor)
	if len(order) != len(o.links) {
		panic("aggregate: INV-4 violated, link order is not a permutation")
	}
	return order
}
