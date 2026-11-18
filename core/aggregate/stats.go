package aggregate

import (
	"net"
	"sync"
	"sync/atomic"
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
	return groups
}
