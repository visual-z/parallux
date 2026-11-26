package pxbridge

import (
	"encoding/json"

	"github.com/visual-z/parallux/core/aggregate"
)

// LinkStatsJSON returns every running aggregate outbound's per-link counters
// as a JSON array of aggregate.GroupStat. JSON because gomobile cannot bind
// slices of structs; the extension forwards it to the app over XPC verbatim.
func LinkStatsJSON() string {
	groups := aggregate.Snapshot()
	if groups == nil {
		groups = []aggregate.GroupStat{}
	}
	data, err := json.Marshal(groups)
	if err != nil {
		return "[]"
	}
	return string(data)
}
