package aggregate

import (
	"net/netip"
	"strings"

	M "github.com/sagernet/sing/common/metadata"
)

// cgnat is RFC 6598 shared address space (carrier NAT, Tailscale); netip
// does not count it as private.
var cgnat = netip.MustParsePrefix("100.64.0.0/10")

// localSuffixes are names that only resolve on the local network.
var localSuffixes = []string{".local", ".lan", ".home.arpa", ".internal"}

// bondEligible reports whether a destination may go through the aggregation
// server (feat-bond-direct). Local destinations never may: the server cannot
// reach the user's NAS or printer. Neither may the hosts in bypass (the
// server itself), which would only loop back to where they started.
//
// The destination may be a name rather than an address, because the tun
// inbound sniffs; local names are judged by their suffix.
func bondEligible(destination M.Socksaddr, bypass []string) bool {
	if destination.IsFqdn() {
		name := strings.ToLower(strings.TrimSuffix(destination.Fqdn, "."))
		if !strings.Contains(name, ".") {
			return false
		}
		for _, suffix := range localSuffixes {
			if strings.HasSuffix(name, suffix) {
				return false
			}
		}
		for _, host := range bypass {
			if strings.EqualFold(host, name) {
				return false
			}
		}
		return true
	}
	addr := destination.Addr.Unmap()
	if !addr.IsValid() || addr.IsUnspecified() || addr.IsLoopback() || addr.IsPrivate() ||
		addr.IsLinkLocalUnicast() || addr.IsLinkLocalMulticast() || addr.IsMulticast() ||
		addr.IsInterfaceLocalMulticast() || cgnat.Contains(addr) {
		return false
	}
	for _, host := range bypass {
		if ip, err := netip.ParseAddr(host); err == nil && ip.Unmap() == addr {
			return false
		}
	}
	return true
}
