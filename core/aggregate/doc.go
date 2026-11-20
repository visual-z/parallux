// Package aggregate is Parallux's policy-group outbound: it spreads the
// connections routed to it over several link outbounds (PLAN decision 12).
//
// Each link is an ordinary sing-box `direct` outbound with `bind_interface`
// set to one physical interface. A node that should use aggregation sets its
// `detour` to an aggregate outbound, so the node list never multiplies by the
// number of links. The global 分流 / 叠加 / 主备 switch in the UI is a preset
// that rewrites the mode of these outbounds.
package aggregate
