package aggregate

// Relay links (中继线路, PLAN decision 24). stubs: feat-relay-links

// relayOrder is the order one connection tries the links in, given the full
// order and which links are relays. stub
func relayOrder(order []int, relay []bool, local bool) []int {
	return order
}

// relayDialFailure classifies a failed dial of a relay link. stub
func relayDialFailure(err error) (retry bool, linkDown bool) {
	return dialFailure(err)
}
