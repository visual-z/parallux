package aggregate

import (
	"context"
	"errors"
	"strings"
	"syscall"
)

// dialFailure says whether a failed dial should try the next link and
// whether it is evidence against this link (fix-dial-errors-poison-health).
//
// Only errors about the link itself mark it unhealthy; everything about the
// destination (a refusal, a firewall timeout, no route to that host) would
// fail the same way on every link, and marking them all down turned 分流
// into "everything on link 0" until the prober caught up. Health is the
// prober's job; a dial failure only adds evidence when it cannot be the
// destination's fault.
func dialFailure(err error) (retry bool, linkDown bool) {
	switch {
	case errors.Is(err, context.Canceled):
		// The caller gave up; nothing was learnt about any link.
		return false, false
	case errors.Is(err, syscall.ECONNREFUSED), errors.Is(err, syscall.ECONNRESET):
		// The destination answered; another link gets the same answer.
		return false, false
	case errors.Is(err, syscall.ENETUNREACH), errors.Is(err, syscall.ENETDOWN),
		errors.Is(err, syscall.EADDRNOTAVAIL), errors.Is(err, syscall.ENXIO),
		strings.Contains(err.Error(), "no such network interface"):
		return true, true
	default:
		// Timeouts, EHOSTUNREACH, TLS and anything unknown: maybe this link,
		// maybe the destination; try the next link but leave health alone.
		return true, false
	}
}
