package pxbridge

import (
	"encoding/json"
	"net"
	"net/netip"
	"strconv"
	"strings"
	"sync"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/adapter"
	C "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/experimental/libbox"
	R "github.com/sagernet/sing-box/route/rule"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
)

var (
	serverAccess  sync.Mutex
	commandServer *libbox.CommandServer
)

// SetCommandServer hands pxbridge the extension's running command server, so
// ExplainRoute can reach its router. The extension calls it once after
// creating the server; nil clears it.
func SetCommandServer(server *libbox.CommandServer) {
	serverAccess.Lock()
	defer serverAccess.Unlock()
	commandServer = server
}

// ExplainRoute reports, as JSON, which route rule a target (domain, IP, or
// host:port) matches in the running configuration and where it goes. It runs
// the router's own rules, so it never drifts from sing-box. JSON because
// gomobile cannot bind structs in slices.
func ExplainRoute(target string) string {
	serverAccess.Lock()
	server := commandServer
	serverAccess.Unlock()
	return explainRouter(serverRouter{server}, target)
}

// routerSource yields the running configuration's box (nil when none).
type routerSource interface{ box() *box.Box }

type serverRouter struct{ server *libbox.CommandServer }

func (s serverRouter) box() *box.Box {
	if s.server == nil || s.server.StartedService == nil {
		return nil
	}
	instance := s.server.Instance()
	if instance == nil {
		return nil
	}
	return instance.Box()
}

type boxRouter struct{ b *box.Box }

func (r boxRouter) box() *box.Box { return r.b }

// Explanation is the JSON shape ExplainRoute returns.
type Explanation struct {
	Target    string `json:"target"`
	RuleIndex int    `json:"rule_index"`
	Rule      string `json:"rule,omitempty"`
	Action    string `json:"action,omitempty"`
	Outbound  string `json:"outbound,omitempty"`
	Final     bool   `json:"final,omitempty"`
	// Skipped counts earlier rules that were checked and did not match.
	Skipped int    `json:"skipped"`
	Error   string `json:"error,omitempty"`
}

func explainRouter(source routerSource, target string) string {
	result := explain(source, strings.TrimSpace(target))
	data, err := json.Marshal(result)
	if err != nil {
		return `{"error":"encode"}`
	}
	return string(data)
}

func explain(source routerSource, target string) Explanation {
	result := Explanation{Target: target, RuleIndex: -1}
	if target == "" {
		result.Error = "empty target"
		return result
	}
	var instance *box.Box
	if source != nil {
		instance = source.box()
	}
	if instance == nil {
		result.Error = "core is not running"
		return result
	}
	metadata := targetMetadata(target)
	router := instance.Router()
	for index, rule := range router.Rules() {
		metadata.ResetRuleCache()
		if !rule.Match(&metadata) {
			result.Skipped++
			continue
		}
		action := rule.Action()
		// Like the router: options-only and sniff actions annotate the
		// connection and matching goes on to the next rule.
		switch action.(type) {
		case *R.RuleActionRouteOptions, *R.RuleActionSniff:
			result.Skipped++
			continue
		}
		result.RuleIndex = index
		result.Rule = rule.String()
		result.Action = action.Type()
		switch typed := action.(type) {
		case *R.RuleActionRoute:
			result.Outbound = typed.Outbound
		case *R.RuleActionBypass:
			result.Outbound = typed.Outbound
		}
		return result
	}
	result.Final = true
	result.Action = C.RuleActionTypeRoute
	if final := instance.Outbound().Default(); final != nil {
		result.Outbound = final.Tag()
	}
	return result
}

// targetMetadata builds what a TCP connection to `target` would carry. Port
// defaults to 443; protocol is guessed from the port, since a dry run cannot sniff.
func targetMetadata(target string) adapter.InboundContext {
	host, portText, err := net.SplitHostPort(target)
	if err != nil {
		host, portText = target, "443"
	}
	port, _ := strconv.Atoi(portText)
	var metadata adapter.InboundContext
	metadata.Network = N.NetworkTCP
	if addr, parseErr := netip.ParseAddr(strings.Trim(host, "[]")); parseErr == nil {
		metadata.Destination = M.SocksaddrFrom(addr, uint16(port))
	} else {
		metadata.Domain = strings.ToLower(host)
		metadata.Destination = M.Socksaddr{Fqdn: metadata.Domain, Port: uint16(port)}
	}
	switch port {
	case 443:
		metadata.Protocol = C.ProtocolTLS
	case 80:
		metadata.Protocol = C.ProtocolHTTP
	case 53:
		metadata.Protocol = C.ProtocolDNS
	}
	return metadata
}
