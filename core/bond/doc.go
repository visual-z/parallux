// Package bond carries the multipath transport behind 叠加 (bond): one TCP
// connection split over several link outbounds ("legs") and reassembled on
// the user's aggregation server (PLAN decision 17).
//
// The protocol is ported from singbox-multipath beta11 (d99530a, GPLv3; see
// docs/LICENSES.md); register.go adds its outbound and inbound types to the
// sing-box fork's hooks so libbox accepts them.
package bond
