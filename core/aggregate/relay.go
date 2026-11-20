package aggregate

import (
	"context"
	"errors"
)

// Relay links (中继线路, PLAN decision 24): links that leave through another
// machine on the LAN instead of one of this Mac's interfaces. To the
// aggregate they are links like any other, with three differences, each for
// the same reason: a relay link's dial ends at the relay host, not at the
// destination.
//
//   - They never carry local destinations (relayOrder): the relay host
//     cannot reach the printer on this Mac's Wi-Fi, and it would not report
//     the failure as a dial error, so there would be no retry.
//   - Every dial error is the link's own (relayDialFailure).
//   - A successful dial proves nothing about the path beyond the relay host,
//     so the prober asks for an answer (health.go, answers).

// relayOrder is the order one connection tries the links in: the full order
// for a public destination, the full order without the relay links for a
// local one (INV-14, docs/INVARIANTS.md).
func relayOrder(order []int, relay []bool, local bool) []int {
	if !local {
		return order
	}
	kept := make([]int, 0, len(order))
	for _, index := range order {
		if !relay[index] {
			kept = append(kept, index)
		}
	}
	return kept
}

// relayDialFailure classifies a failed dial of a relay link. Unlike
// dialFailure, a refusal or a timeout here cannot be the destination's
// answer: the proxy handshake is lazy, so the dial only reaches the relay
// host. Try the next link and count it against this one. Only the caller
// giving up says nothing.
func relayDialFailure(err error) (retry bool, linkDown bool) {
	if errors.Is(err, context.Canceled) {
		return false, false
	}
	return true, true
}
