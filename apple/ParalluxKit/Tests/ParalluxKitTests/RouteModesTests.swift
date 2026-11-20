import Foundation
import Testing
@testable import ParalluxKit

private func root(_ json: String) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
}

private func rules(_ json: String) throws -> [[String: Any]] {
    ((try root(json)["route"] as? [String: Any])?["rules"] as? [[String: Any]]) ?? []
}

private func outbounds(_ json: String) throws -> [[String: Any]] {
    (try root(json)["outbounds"] as? [[String: Any]]) ?? []
}

/// A rule as comparable JSON.
private func text(_ value: Any) -> String {
    String(decoding: (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data(), as: UTF8.self)
}

private func profile(outbounds: String, rules: String?, final: String? = "Proxy", dns: String = #"{"servers": [{"type": "local", "tag": "local"}]}"#) -> String {
    var route: [String] = []
    if let rules { route.append(#""rules": \#(rules)"#) }
    if let final { route.append(#""final": "\#(final)""#) }
    return """
    {"dns": \(dns), "inbounds": [{"type": "tun", "tag": "tun-in", "auto_route": true}],
     "outbounds": \(outbounds), "route": {\(route.joined(separator: ", "))}}
    """
}

private let usualOutbounds = """
[{"type": "selector", "tag": "Proxy", "outbounds": ["DE-01", "Auto", "direct"]},
 {"type": "urltest", "tag": "Auto", "outbounds": ["DE-01"]},
 {"type": "vless", "tag": "DE-01", "server": "de.example.com", "server_port": 443, "uuid": "00000000-0000-0000-0000-000000000000"},
 {"type": "direct", "tag": "direct"},
 {"type": "block", "tag": "block"}]
"""

private let usualRules = """
[{"action": "sniff"},
 {"protocol": "dns", "action": "hijack-dns"},
 {"ip_is_private": true, "outbound": "direct"},
 {"rule_set": "geosite-cn", "outbound": "direct"},
 {"domain_suffix": ["example.org"], "outbound": "DE-01"}]
"""

private let directRule = #"{"clash_mode":"Direct","outbound":"direct"}"#
private func globalRule(_ target: String) -> String {
    #"{"mode":"and","outbound":"\#(target)","rules":[{"clash_mode":"Global"},{"invert":true,"ip_is_private":true}],"type":"logical"}"#
}

@Suite struct RouteModesTests {
    /// A subscription that defines no modes: sing-box offers only 规则, and
    /// the mode control has nothing to switch to. Two rules give it 直连 and
    /// 全局, placed where they decide before the profile's own rules but
    /// after the rules that only prepare a connection.
    @Test func aProfileWithoutModesGetsDirectAndGlobal() throws {
        let before = profile(outbounds: usualOutbounds, rules: usualRules)
        let after = RouteModes.add(to: before)
        let was = try rules(before), now = try rules(after)
        try #require(now.count == was.count + 2)
        #expect(now[0...1].map(text) == was[0...1].map(text), "sniff and hijack-dns stay first")
        #expect(text(now[2]) == directRule)
        #expect(text(now[3]) == globalRule("Proxy"), "全局 goes where the profile sends everything else, and leaves the LAN to the profile's rules")
        #expect(now[4...].map(text) == was[2...].map(text), "the profile's own rules follow, in order")
        // Nothing else changes, except that names resolve locally in 直连.
        var a = try root(before), b = try root(after)
        a["route"] = nil; b["route"] = nil
        let dnsBefore = try #require(a.removeValue(forKey: "dns") as? [String: Any])
        let dnsAfter = try #require(b.removeValue(forKey: "dns") as? [String: Any])
        #expect(text(a) == text(b))
        #expect(text(dnsAfter["servers"] as Any) == text(dnsBefore["servers"] as Any))
        #expect(text(dnsAfter["rules"] as Any) == #"[{"clash_mode":"Direct","server":"local"}]"#)
        #expect((try root(after)["route"] as? [String: Any])?["final"] as? String == "Proxy")
    }

    @Test func aProfileWithItsOwnModesIsLeftAlone() throws {
        let own = [
            #"[{"action": "sniff"}, {"clash_mode": "direct", "outbound": "direct"}, {"clash_mode": "global", "outbound": "Proxy"}]"#,
            #"[{"type": "logical", "mode": "or", "rules": [{"clash_mode": "Global"}, {"port": 443}], "outbound": "Proxy"}]"#,
            #"[{"clash_mode": "Streaming", "outbound": "DE-01"}]"#,
        ]
        for rules in own {
            let before = profile(outbounds: usualOutbounds, rules: rules)
            #expect(RouteModes.add(to: before) == before, "\(rules)")
        }
        // Modes that only the DNS rules name count too.
        let dns = #"{"servers": [{"type": "local", "tag": "local"}], "rules": [{"clash_mode": "Direct", "server": "local"}]}"#
        let before = profile(outbounds: usualOutbounds, rules: usualRules, dns: dns)
        #expect(RouteModes.add(to: before) == before)
        // And what is not a profile at all.
        #expect(RouteModes.add(to: "not json") == "not json")
        #expect(RouteModes.add(to: "[1, 2]") == "[1, 2]")
    }

    @Test func globalTargetsTheProfilesMainProxy() throws {
        func targets(_ outbounds: String, final: String?) throws -> (direct: String?, global: String?, added: [String]) {
            let before = profile(outbounds: outbounds, rules: "[]", final: final)
            let after = RouteModes.add(to: before)
            let now = try rules(after)
            let direct = now.first { $0["clash_mode"] as? String == "Direct" }?["outbound"] as? String
            let global = now.first { $0["type"] as? String == "logical" }?["outbound"] as? String
            let tags = Set(try ParalluxKitTests.outbounds(before).compactMap { $0["tag"] as? String })
            let added = try ParalluxKitTests.outbounds(after).compactMap { $0["tag"] as? String }.filter { !tags.contains($0) }
            return (direct, global, added)
        }
        // final names a group: that group.
        #expect(try targets(usualOutbounds, final: "Proxy").global == "Proxy")
        #expect(try targets(usualOutbounds, final: "Auto").global == "Auto")
        // final names a node: that node.
        #expect(try targets(usualOutbounds, final: "DE-01").global == "DE-01")
        // final is direct or block (a whitelist profile): the first group.
        #expect(try targets(usualOutbounds, final: "direct").global == "Proxy")
        #expect(try targets(usualOutbounds, final: "block").global == "Proxy")
        // No final: sing-box uses the first outbound.
        #expect(try targets(usualOutbounds, final: nil).global == "Proxy")
        // No group anywhere: the first node.
        let nodes = #"[{"type": "direct", "tag": "direct"}, {"type": "trojan", "tag": "JP", "server": "jp.example.com", "server_port": 443, "password": "x"}, {"type": "vless", "tag": "DE", "server": "de.example.com", "server_port": 443, "uuid": "00000000-0000-0000-0000-000000000000"}]"#
        #expect(try targets(nodes, final: "direct").global == "JP")
        // A final that names nothing: as if there were none.
        #expect(try targets(nodes, final: "gone").global == "JP")
        // Nothing to proxy through: 直连 only.
        let onlyDirect = #"[{"type": "direct", "tag": "out"}]"#
        let plain = try targets(onlyDirect, final: "out")
        #expect(plain.global == nil)
        #expect(plain.direct == "out", "the profile's own direct outbound, whatever it is called")
        #expect(plain.added.isEmpty)
        // No direct outbound: one is added, under a tag nobody uses.
        let noDirect = #"[{"type": "selector", "tag": "Proxy", "outbounds": ["DE"]}, {"type": "vless", "tag": "DE", "server": "de.example.com", "server_port": 443, "uuid": "00000000-0000-0000-0000-000000000000"}]"#
        let added = try targets(noDirect, final: "Proxy")
        #expect(added.direct == "direct")
        #expect(added.added == ["direct"])
        let taken = #"[{"type": "selector", "tag": "direct", "outbounds": ["DE"]}, {"type": "vless", "tag": "DE", "server": "de.example.com", "server_port": 443, "uuid": "00000000-0000-0000-0000-000000000000"}]"#
        let renamed = try targets(taken, final: "direct")
        #expect(renamed.direct == "parallux-direct", "a group that happens to be called direct is not a direct outbound")
        #expect(renamed.added == ["parallux-direct"])
        #expect(renamed.global == "direct")
        // No outbounds at all: only a direct one, and 直连.
        let empty = try targets("[]", final: nil)
        #expect(empty.direct == "direct")
        #expect(empty.global == nil)
    }

    @Test func modeRulesComeAfterTheRulesThatOnlyPrepareAConnection() throws {
        func position(_ rules: String?, outbounds: String = usualOutbounds) throws -> Int? {
            let after = RouteModes.add(to: profile(outbounds: outbounds, rules: rules))
            return try ParalluxKitTests.rules(after).firstIndex { $0["clash_mode"] as? String == "Direct" }
        }
        // No rules, or an empty list: the mode rules are all there is.
        #expect(try position(nil) == 0)
        #expect(try position("[]") == 0)
        // The first rule already decides where traffic goes.
        #expect(try position(#"[{"rule_set": "geosite-cn", "outbound": "direct"}, {"action": "sniff"}]"#) == 0)
        #expect(try position(#"[{"ip_is_private": true, "action": "reject"}]"#) == 0)
        #expect(try position(#"[{"port": 53, "action": "route", "outbound": "direct"}]"#) == 0)
        // Preparing rules, with conditions or without, are passed over.
        #expect(try position(#"[{"inbound": "tun-in", "action": "sniff"}, {"action": "resolve"}, {"port": 53, "action": "hijack-dns"}, {"action": "route-options", "udp_timeout": "1m"}]"#) == 4)
        // The older way to hand DNS over: an outbound of type dns.
        let legacy = #"[{"type": "dns", "tag": "dns-out"}, {"type": "selector", "tag": "Proxy", "outbounds": ["direct"]}, {"type": "direct", "tag": "direct"}]"#
        #expect(try position(#"[{"protocol": "dns", "outbound": "dns-out"}, {"port": 443, "outbound": "Proxy"}]"#, outbounds: legacy) == 1)
        // Only the leading run counts: a sniff further down stays where it is.
        #expect(try position(#"[{"action": "sniff"}, {"port": 443, "outbound": "Proxy"}, {"action": "sniff"}]"#) == 1)
    }

    /// For any profile: the user's rules survive in order, every outbound a
    /// rule names exists, and adding twice is adding once.
    @Test func addingModesKeepsEveryRuleAndNeverDangles() throws {
        var rng = SplitMix64(seed: 0x26)
        let ruleBank = [
            #"{"action": "sniff"}"#, #"{"protocol": "dns", "action": "hijack-dns"}"#, #"{"action": "resolve"}"#,
            #"{"ip_is_private": true, "outbound": "direct"}"#, #"{"rule_set": "geosite-cn", "outbound": "direct"}"#,
            #"{"domain_suffix": ["example.org"], "outbound": "DE-01"}"#, #"{"port": 22, "action": "reject"}"#,
            #"{"clash_mode": "Global", "outbound": "Proxy"}"#,
        ]
        var injected = 0
        for _ in 0..<300 {
            let picked = ruleBank.filter { _ in rng.int(3) == 0 }
            let final: String? = [nil, "Proxy", "direct", "DE-01", "block", "gone"][rng.int(6)]
            let before = profile(outbounds: usualOutbounds, rules: rng.int(8) == 0 ? nil : "[\(picked.joined(separator: ", "))]", final: final)
            let after = RouteModes.add(to: before)
            #expect(RouteModes.add(to: after) == after, "adding twice is adding once")
            let was = try rules(before).map(text), now = try rules(after)
            let own = now.filter { rule in
                let json = text(rule)
                return json != directRule && !(rule["type"] as? String == "logical" && json.contains(#""clash_mode":"Global""#) && json.contains(#""invert":true"#))
            }
            #expect(own.map(text) == was, "the profile's rules, in order")
            // From the rules the profile really has: one round in eight has
            // no rules at all, whatever was picked.
            let hadModes = was.contains { $0.contains("clash_mode") }
            #expect(now.count == was.count + (hadModes ? 0 : 2))
            if !hadModes { injected += 1 }
            let tags = Set(try outbounds(after).compactMap { $0["tag"] as? String })
            for rule in now { if let outbound = rule["outbound"] as? String { #expect(tags.contains(outbound), "a rule names \(outbound), which does not exist") } }
        }
        #expect(injected > 100, "the generator rarely produced a profile without modes (\(injected))")
    }

    /// 直连 is where people go when the node is down; a DNS server reached
    /// through the node would then resolve nothing.
    @Test func directModeResolvesNamesWithTheProfilesLocalServer() throws {
        func dnsRules(_ dns: String) throws -> [String] {
            let after = RouteModes.add(to: profile(outbounds: usualOutbounds, rules: usualRules, dns: dns))
            return ((try root(after)["dns"] as? [String: Any])?["rules"] as? [[String: Any]] ?? []).map(text)
        }
        let rule = { (server: String) in #"{"clash_mode":"Direct","server":"\#(server)"}"# }
        // In front of the profile's own DNS rules, which stay in order.
        #expect(try dnsRules(#"{"servers": [{"type": "https", "tag": "remote", "server": "dns.example.com", "detour": "Proxy"}, {"type": "local", "tag": "system"}], "rules": [{"rule_set": "geosite-cn", "server": "system"}, {"port": 53, "server": "remote"}]}"#)
            == [rule("system"), #"{"rule_set":"geosite-cn","server":"system"}"#, #"{"port":53,"server":"remote"}"#])
        // The format before sing-box 1.12.
        #expect(try dnsRules(#"{"servers": [{"tag": "remote", "address": "https://dns.example.com/dns-query"}, {"tag": "old-local", "address": "local"}]}"#) == [rule("old-local")])
        // No local server, a local server without a tag, or no servers: nothing is added.
        #expect(try dnsRules(#"{"servers": [{"type": "https", "tag": "remote", "server": "dns.example.com"}]}"#).isEmpty)
        #expect(try dnsRules(#"{"servers": [{"type": "local"}]}"#).isEmpty)
        #expect(try dnsRules("{}").isEmpty)
        // A profile without a dns section gets none.
        let bare = RouteModes.add(to: #"{"outbounds": [{"type": "direct", "tag": "direct"}]}"#)
        #expect(try root(bare)["dns"] == nil)
    }

    /// The names the overview and the connections page show for a
    /// connection that a mode rule decided, from sing-box's own wording.
    @Test func connectionsDecidedByAModeAreNamedAfterIt() {
        #expect(TrafficLabel.name(connectionRule: "clash_mode=Direct") == "直连模式")
        #expect(TrafficLabel.name(connectionRule: "clash_mode=Global && !(ip_is_private=true)") == "全局模式")
        #expect(TrafficLabel.name(connectionRule: "clash_mode=global") == "全局模式", "a profile's own lower-case mode")
        #expect(TrafficLabel.name(connectionRule: "ip_is_private=true") == "局域网", "a plain LAN rule keeps its name")
    }
}

extension RouteModesTests {
    static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("core/aggregate/testdata/composed-modes.json")
    }

    /// core/pxbridge checks this fixture with libbox.CheckConfig; the two
    /// steps must keep producing exactly it. PARALLUX_WRITE_FIXTURES=1
    /// rewrites it (then read the diff).
    @Test func composedModesFixtureMatchesTheGenerator() throws {
        let links = [LinkInterface(name: "en0", kind: .wifi, displayName: "Wi‑Fi"), LinkInterface(name: "en7", kind: .ethernet, displayName: "USB LAN")]
        let withModes = RouteModes.add(to: profile(outbounds: usualOutbounds, rules: #"[{"action": "sniff"}, {"protocol": "dns", "action": "hijack-dns"}, {"ip_is_private": true, "outbound": "direct"}, {"domain_suffix": ["example.org"], "outbound": "DE-01"}]"#))
        let generatedText = try ProfileComposer.compose(withModes, links: links, backup: [], mode: .balance)
        if ProcessInfo.processInfo.environment["PARALLUX_WRITE_FIXTURES"] == "1" {
            try Data((generatedText + "\n").utf8).write(to: Self.fixtureURL)
        }
        let expected = (try? Data(contentsOf: Self.fixtureURL)).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? NSDictionary
        let generated = try JSONSerialization.jsonObject(with: Data(generatedText.utf8)) as? NSDictionary
        #expect(expected != nil, "core/aggregate/testdata/composed-modes.json is missing")
        #expect(generated == expected)
        #expect(generatedText.contains(#""clash_mode" : "Global""#), "the fixture carries the modes")
    }
}
