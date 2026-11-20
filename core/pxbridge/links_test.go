package pxbridge

import (
	"encoding/json"
	"testing"
)

func TestLinkStatsJSONIsAnArrayEvenWithNoAggregate(t *testing.T) {
	var groups []map[string]any
	if err := json.Unmarshal([]byte(LinkStatsJSON()), &groups); err != nil {
		t.Fatalf("LinkStatsJSON is not a JSON array: %v", err)
	}
	if groups == nil {
		t.Fatal("LinkStatsJSON returned null, want []")
	}
}
