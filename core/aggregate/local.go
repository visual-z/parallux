package aggregate

import M "github.com/sagernet/sing/common/metadata"

// bondEligible reports whether a destination may go through the aggregation
// server (feat-bond-direct). stub
func bondEligible(destination M.Socksaddr, bypass []string) bool {
	return true
}
