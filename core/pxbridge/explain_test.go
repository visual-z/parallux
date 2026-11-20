package pxbridge

import (
	"context"
	"encoding/json"
	"testing"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
	sjson "github.com/sagernet/sing/common/json"
)

const explainConfig = `{
  "log": {"disabled": true},
  "outbounds": [
    {"type": "direct", "tag": "direct"},
    {"type": "direct", "tag": "proxy-stand-in"},
    {"type": "block", "tag": "block"}
  ],
  "route": {
    "rules": [
      {"action": "sniff"},
      {"ip_is_private": true, "outbound": "direct"},
      {"domain_suffix": ["youtube.com", "googlevideo.com"], "outbound": "proxy-stand-in"},
      {"domain": ["ads.example.com"], "action": "reject"}
    ],
    "final": "proxy-stand-in"
  }
}`

type explained struct {
	Target    string `json:"target"`
	RuleIndex int    `json:"rule_index"`
	Rule      string `json:"rule"`
	Action    string `json:"action"`
	Outbound  string `json:"outbound"`
	Final     bool   `json:"final"`
	Error     string `json:"error"`
}

func explainWith(t *testing.T, target string) explained {
	t.Helper()
	var out explained
	if err := json.Unmarshal([]byte(explainRouter(testRouter, target)), &out); err != nil {
		t.Fatalf("ExplainRoute(%q) is not JSON: %v", target, err)
	}
	return out
}

var testRouter routerSource

func TestExplainRouteReportsTheMatchingRule(t *testing.T) {
	ctx := include.Context(context.Background())
	options, err := sjson.UnmarshalExtendedContext[option.Options](ctx, []byte(explainConfig))
	if err != nil {
		t.Fatal(err)
	}
	instance, err := box.New(box.Options{Options: options, Context: ctx})
	if err != nil {
		t.Fatal(err)
	}
	if err := instance.Start(); err != nil {
		t.Fatal(err)
	}
	defer instance.Close()
	testRouter = boxRouter{instance}

	yt := explainWith(t, "www.youtube.com")
	if yt.RuleIndex != 2 || yt.Outbound != "proxy-stand-in" || yt.Final {
		t.Fatalf("youtube = %+v, want rule 2 to proxy-stand-in", yt)
	}
	lan := explainWith(t, "192.168.1.20")
	if lan.RuleIndex != 1 || lan.Outbound != "direct" {
		t.Fatalf("LAN = %+v, want rule 1 to direct", lan)
	}
	ad := explainWith(t, "ads.example.com:443")
	if ad.RuleIndex != 3 || ad.Action != "reject" || ad.Outbound != "" {
		t.Fatalf("ad = %+v, want rule 3 reject", ad)
	}
	other := explainWith(t, "example.org")
	if !other.Final || other.Outbound != "proxy-stand-in" || other.RuleIndex != -1 {
		t.Fatalf("unmatched = %+v, want final proxy-stand-in", other)
	}
	if got := explainWith(t, ""); got.Error == "" {
		t.Fatalf("empty target = %+v, want an error", got)
	}
}
