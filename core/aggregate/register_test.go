package aggregate_test

import (
	"strings"
	"testing"

	"github.com/sagernet/sing-box/experimental/libbox"

	_ "github.com/visual-z/parallux/core/aggregate"
)

// config wraps one aggregate outbound over two direct link outbounds.
func config(aggregate string) string {
	return `{
  "outbounds": [
    {"type": "direct", "tag": "link-en0", "bind_interface": "en0"},
    {"type": "direct", "tag": "link-en7", "bind_interface": "en7"},
    ` + aggregate + `
  ]
}`
}

func TestLibboxResolvesTheAggregateOutboundTypeToParallux(t *testing.T) {
	err := libbox.CheckConfig(config(`{"type": "aggregate", "tag": "agg", "mode": "failover", "links": ["link-en0", "link-en7"]}`))
	if err != nil && strings.Contains(err.Error(), "unknown outbound type") {
		t.Fatalf("libbox does not know the aggregate type, so the registration hook is not wired: %v", err)
	}
	if err != nil {
		t.Fatalf("a valid failover aggregate over two links should pass CheckConfig: %v", err)
	}
}

func TestAggregateRejectsAnEmptyLinkList(t *testing.T) {
	err := libbox.CheckConfig(config(`{"type": "aggregate", "tag": "agg", "mode": "balance", "links": []}`))
	if err == nil || !strings.Contains(err.Error(), "links") {
		t.Fatalf("CheckConfig with no links = %v, want an error naming links", err)
	}
}

func TestAggregateRejectsAnUnknownMode(t *testing.T) {
	err := libbox.CheckConfig(config(`{"type": "aggregate", "tag": "agg", "mode": "turbo", "links": ["link-en0"]}`))
	if err == nil || !strings.Contains(err.Error(), "turbo") {
		t.Fatalf("CheckConfig with mode turbo = %v, want an error naming the mode", err)
	}
}
