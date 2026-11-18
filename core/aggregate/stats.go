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
	return conn
}

// registry holds the running aggregate outbounds for Snapshot.
var registry sync.Map // tag → *Outbound

// Snapshot returns every running aggregate outbound's per-link statistics.
func Snapshot() []GroupStat {
	return nil
}
