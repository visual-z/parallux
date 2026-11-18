package aggregate

// linkOrder returns the indices of n links in the order one connection should
// try them (INV-4, docs/INVARIANTS.md).
//
//   - failover: healthy primaries in priority order, then healthy backups,
//     then unhealthy links (still tried: health is a guess, a dial is truth).
//   - balance: the healthy primaries rotated by cursor, then the rest as for
//     failover.
//   - bond: the same as failover; the bond outbound is tried before all of them.
func linkOrder(mode string, healthy, backup []bool, cursor uint64) []int {
	n := len(healthy)
	order := make([]int, 0, n)
	var primaries []int
	for i := range n {
		if healthy[i] && !backup[i] {
			primaries = append(primaries, i)
		}
	}
	if mode == ModeBalance && len(primaries) > 1 {
		start := int(cursor % uint64(len(primaries)))
		primaries = append(primaries[start:], primaries[:start]...)
	}
	order = append(order, primaries...)
	for i := range n {
		if healthy[i] && backup[i] {
			order = append(order, i)
		}
	}
	for i := range n {
		if !healthy[i] {
			order = append(order, i)
		}
	}
	return order
}
