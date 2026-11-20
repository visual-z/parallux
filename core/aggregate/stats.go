package aggregate

import (
	"net"
	"slices"
	"strings"
	"sync"
	"sync/atomic"

	"github.com/sagernet/sing/common/buf"
	"github.com/sagernet/sing/common/bufio"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
)

// linkCounters are one link's totals inside one aggregate outbound.
type linkCounters struct {
	upload   atomic.Int64
	download atomic.Int64
	active   atomic.Int64
}

// LinkStat is the JSON shape pxbridge exposes to the app.
type LinkStat struct {
	Tag      string `json:"tag"`
	Healthy  bool   `json:"healthy"`
	Backup   bool   `json:"backup"`
	Upload   int64  `json:"upload"`
	Download int64  `json:"download"`
	Active   int64  `json:"active"`
}

// GroupStat is one aggregate outbound's links.
type GroupStat struct {
	Tag   string     `json:"tag"`
	Mode  string     `json:"mode"`
	Links []LinkStat `json:"links"`
}

// countedConn adds its traffic to one link's counters.
type countedConn struct {
	net.Conn
	counters *linkCounters
	once     sync.Once
}

func newCountedConn(conn net.Conn, counters *linkCounters) net.Conn {
	counters.active.Add(1)
	return &countedConn{Conn: conn, counters: counters}
}

func (c *countedConn) Read(p []byte) (int, error) {
	n, err := c.Conn.Read(p)
	c.counters.download.Add(int64(n))
	return n, err
}

func (c *countedConn) Write(p []byte) (int, error) {
	n, err := c.Conn.Write(p)
	c.counters.upload.Add(int64(n))
	return n, err
}

func (c *countedConn) Close() error {
	c.once.Do(func() { c.counters.active.Add(-1) })
	return c.Conn.Close()
}

// Upstream exposes the wrapped connection to sing's bufio fast paths.
func (c *countedConn) Upstream() any { return c.Conn }

// countedPacketConn adds a relay link's UDP traffic to its counters, and
// counts as one active connection until closed.
//
// Only relay links get one (feat-relay-links): a physical link's bytes are
// read from its interface, which sees everything, and wrapping its packet
// conns would hide sing's fast paths for no information. A relay link's
// bytes are mixed into its carrier's interface, so these counters are the
// only place they can be told apart.
type countedPacketConn struct {
	N.NetPacketConn
	counters *linkCounters
	once     sync.Once
}

func newCountedPacketConn(conn net.PacketConn, counters *linkCounters) net.PacketConn {
	counters.active.Add(1)
	return &countedPacketConn{NetPacketConn: bufio.NewPacketConn(conn), counters: counters}
}

func (c *countedPacketConn) ReadFrom(p []byte) (int, net.Addr, error) {
	n, addr, err := c.NetPacketConn.ReadFrom(p)
	c.counters.download.Add(int64(n))
	return n, addr, err
}

func (c *countedPacketConn) WriteTo(p []byte, addr net.Addr) (int, error) {
	n, err := c.NetPacketConn.WriteTo(p, addr)
	c.counters.upload.Add(int64(n))
	return n, err
}

func (c *countedPacketConn) ReadPacket(buffer *buf.Buffer) (M.Socksaddr, error) {
	before := buffer.Len()
	destination, err := c.NetPacketConn.ReadPacket(buffer)
	if err == nil {
		c.counters.download.Add(int64(buffer.Len() - before))
	}
	return destination, err
}

func (c *countedPacketConn) WritePacket(buffer *buf.Buffer, destination M.Socksaddr) error {
	// The writer releases the buffer, so its length is read first.
	n := buffer.Len()
	err := c.NetPacketConn.WritePacket(buffer, destination)
	if err == nil {
		c.counters.upload.Add(int64(n))
	}
	return err
}

func (c *countedPacketConn) Close() error {
	c.once.Do(func() { c.counters.active.Add(-1) })
	return c.NetPacketConn.Close()
}

// Upstream exposes the wrapped connection to sing's bufio fast paths.
func (c *countedPacketConn) Upstream() any { return c.NetPacketConn }

// registry holds the running aggregate outbounds for Snapshot.
var registry sync.Map // tag → *Outbound

// Snapshot returns every running aggregate outbound's per-link statistics.
func Snapshot() []GroupStat {
	var groups []GroupStat
	registry.Range(func(_, value any) bool {
		o := value.(*Outbound)
		healthy := o.healthSnapshot()
		group := GroupStat{Tag: o.Tag(), Mode: o.mode}
		for i, tag := range o.tags {
			stat := LinkStat{Tag: tag, Healthy: healthy[i], Backup: o.backup[i]}
			if i < len(o.counters) && o.counters[i] != nil {
				stat.Upload = o.counters[i].upload.Load()
				stat.Download = o.counters[i].download.Load()
				stat.Active = o.counters[i].active.Load()
			}
			group.Links = append(group.Links, stat)
		}
		groups = append(groups, group)
		return true
	})
	// sync.Map ranges in random order; the app compares samples group by group.
	slices.SortFunc(groups, func(a, b GroupStat) int { return strings.Compare(a.Tag, b.Tag) })
	return groups
}
