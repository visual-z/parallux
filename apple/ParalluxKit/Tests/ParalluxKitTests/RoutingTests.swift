import Foundation
import Testing
@testable import ParalluxKit

private let routingProfile = """
{
  "outbounds": [
    {"type": "selector", "tag": "proxy", "outbounds": ["DE Auto", "US Auto", "direct"]},
    {"type": "urltest", "tag": "DE Auto", "outbounds": ["DE-1 AnyTLS"]},
    {"type": "selector", "tag": "流媒体", "outbounds": ["IPLC · 香港 02"]},
    {"type": "direct", "tag": "direct"}
  ],
  "route": {
    "rules": [
      {"action": "sniff"},
      {"protocol": "dns", "action": "hijack-dns"},
      {"ip_is_private": true, "outbound": "direct"},
      {"rule_set": "geosite-youtube", "outbound": "流媒体"},
      {"domain_suffix": ["github.com", "githubusercontent.com"], "outbound": "proxy"},
      {"rule_set": ["geosite-cn", "geoip-cn"], "outbound": "direct"}
    ],
    "final": "proxy"
  }
}
"""

private func group(_ tag: String, _ type: String, selected: String, _ items: [String]) -> OutboundGroupModel {
    OutboundGroupModel(tag: tag, type: type, selectable: type == "selector", selected: selected,
                       items: items.map { .init(tag: $0, type: "x", delay: 0) })
}

@Suite struct ExitChainTests {
    @Test func exitChainsFlattenAndStopOnCycles() {
        let groups = [
            group("proxy", "selector", selected: "DE Auto", ["DE Auto", "US Auto"]),
            group("DE Auto", "urltest", selected: "DE-1 AnyTLS", ["DE-1 AnyTLS"]),
            group("a", "selector", selected: "b", ["b"]),
            group("b", "selector", selected: "a", ["a"]),
            group("lost", "selector", selected: "gone", ["gone"]),
        ]
        let outbounds: Set<String> = ["proxy", "DE Auto", "DE-1 AnyTLS", "direct", "a", "b", "lost"]
        #expect(ExitChain.flatten("proxy", groups: groups, outbounds: outbounds) == ExitChain(hops: ["proxy", "DE Auto", "DE-1 AnyTLS"], ending: .node))
        #expect(ExitChain.flatten("direct", groups: groups, outbounds: outbounds) == ExitChain(hops: ["direct"], ending: .node))
        #expect(ExitChain.flatten("a", groups: groups, outbounds: outbounds).ending == .cycle)
        #expect(ExitChain.flatten("lost", groups: groups, outbounds: outbounds) == ExitChain(hops: ["lost", "gone"], ending: .missing("gone")))
        // A chain deeper than the cap stops there.
        let deep = (0...12).map { group("g\($0)", "selector", selected: "g\($0 + 1)", ["g\($0 + 1)"]) }
        let deepChain = ExitChain.flatten("g0", groups: deep, outbounds: Set((0...13).map { "g\($0)" }))
        #expect(deepChain.ending == .tooDeep)
        #expect(deepChain.hops.count <= ExitChain.maxDepth + 1)
    }
}

@Suite struct RouteMapTests {
    @Test func theRouteMapGroupsTrafficByRule() throws {
        let profile = RouteProfile.parse(routingProfile)
        #expect(profile.final == "proxy")
        try #require(profile.rules.count == 6)
        #expect(profile.rules.map(\.outbound) == [nil, nil, "direct", "流媒体", "proxy", "direct"])
        func row(_ id: String, rule: String, rate: Int64) -> ConnectionRow {
            ConnectionRow(id: id, process: "", destination: "", rule: rule, outbound: "", downlink: rate)
        }
        let connections = [
            row("1", rule: "rule_set=geosite-youtube", rate: 1000),
            row("2", rule: "rule_set=geosite-youtube", rate: 500),
            row("3", rule: "", rate: 70),
            row("4", rule: "rule_set=[geosite-cn geoip-cn]", rate: 300),
        ]
        let map = RouteMap.build(profile: profile, connections: connections, labels: [4: "开发"], overridden: [3])
        // Route rules only (sniff and hijack-dns hidden), plus final.
        // Rate descending, ties in rule order, final last among equals.
        #expect(map.classes.map(\.ruleIndex) == [3, 5, nil, 2, 4])
        let youtube = try #require(map.classes.first { $0.ruleIndex == 3 })
        #expect(youtube.rate == 1500)
        #expect(youtube.connections == 2)
        #expect(youtube.exit == "流媒体")
        #expect(youtube.overridden)
        #expect(map.classes.first { $0.ruleIndex == 4 }?.name == "开发", "a user label wins")
        let final = try #require(map.classes.first { $0.ruleIndex == nil })
        #expect(final.name == TrafficLabel.finalName)
        #expect(final.rate == 70)
        #expect(final.exit == "proxy")
        #expect(map.classes.first?.rate == 1500, "sorted by rate")
        #expect(Set(map.exits) == ["流媒体", "direct", "proxy"])

        // More than the cap: the slowest are merged.
        let many = RouteProfile(rules: (0..<20).map { RouteRule(index: $0, condition: "domain=d\($0)", items: ["domain": ["d\($0)"]], outbound: "proxy", action: "route") }, final: "direct")
        let busy = (0..<20).map { row("\($0)", rule: "domain=d\($0)", rate: Int64($0 + 1)) }
        let capped = RouteMap.build(profile: many, connections: busy)
        #expect(capped.classes.count == RouteMap.maxClasses)
        #expect(capped.hiddenCount == 21 - RouteMap.maxClasses)
        #expect(capped.classes.allSatisfy { $0.rate >= 9 })
        #expect(RouteMap.build(profile: RouteProfile(rules: [], final: nil), connections: []).classes.isEmpty)
    }

    @Test func trafficLabelsReadLikeTheDesign() {
        func rule(_ items: [String: [String]]) -> RouteRule {
            RouteRule(index: 0, condition: "", items: items, outbound: "proxy", action: "route")
        }
        #expect(TrafficLabel.name(for: rule(["rule_set": ["geosite-youtube"]])) == "YouTube")
        #expect(TrafficLabel.name(for: rule(["rule_set": ["geosite-cn", "geoip-cn"]])) == "中国大陆")
        #expect(TrafficLabel.name(for: rule(["ip_is_private": ["true"]])) == "局域网")
        #expect(TrafficLabel.name(for: rule(["domain_suffix": ["github.com", "githubusercontent.com"]])) == "github.com 等 2 项")
        #expect(TrafficLabel.name(for: rule(["process_name": ["Steam"]])) == "Steam")
        #expect(TrafficLabel.name(for: rule(["rule_set": ["geosite-some-unknown-list"]])) == "some-unknown-list")
        #expect(!TrafficLabel.name(for: rule([:])).isEmpty)
    }

    @Test func nodeRegionsAndMultipliersAreInferred() {
        #expect(NodeTraits.infer("🇩🇪 DE-1 AnyTLS") == NodeTraits(region: "德国", multiplier: nil))
        #expect(NodeTraits.infer("IPLC · 香港 0.5倍率") == NodeTraits(region: "香港", multiplier: "0.5 倍率"))
        #expect(NodeTraits.infer("US-2 Reality x2") == NodeTraits(region: "美国", multiplier: "2 倍率"))
        #expect(NodeTraits.infer("IPLC · 狮城 0.5 倍率").region == "新加坡")
        #expect(NodeTraits.infer("JP 东京 01").region == "日本")
        #expect(NodeTraits.infer("Ghelper").region == NodeTraits.otherRegion)
        #expect(NodeTraits.infer("").region == NodeTraits.otherRegion)
        #expect(LatencyGrade(milliseconds: 0) == .untested)
        #expect(LatencyGrade(milliseconds: 1) == .fast)
        #expect(LatencyGrade(milliseconds: 399) == .fast)
        #expect(LatencyGrade(milliseconds: 400) == .medium)
        #expect(LatencyGrade(milliseconds: 799) == .medium)
        #expect(LatencyGrade(milliseconds: 800) == .slow)
    }
}

@Suite struct RouteOverrideTests {
    @Test func overridesOnlyTouchTheirRulesAndNeverDangle() throws {
        let profile = RouteProfile.parse(routingProfile)
        try #require(profile.rules.count == 6)
        func rules(_ config: String) throws -> [[String: Any]] {
            let root = try #require(try JSONSerialization.jsonObject(with: Data(config.utf8)) as? [String: Any])
            return try #require((root["route"] as? [String: Any])?["rules"] as? [[String: Any]])
        }
        let before = try rules(routingProfile)
        let tags: Set<String> = ["proxy", "DE Auto", "流媒体", "direct"]
        var rng = SplitMix64(seed: 0x20)
        for _ in 0..<200 {
            var overrides = RouteOverrides()
            for rule in profile.rules where rng.int(3) == 0 {
                let target = rng.int(5) == 0 ? "no-such-outbound" : ["proxy", "流媒体", "direct"][rng.int(3)]
                let fingerprint = rng.int(6) == 0 ? "stale" : rule.condition
                overrides.items.append(RouteOverride(ruleIndex: rule.index, fingerprint: fingerprint, outbound: target))
            }
            let result = RouteOverrides.apply(overrides, to: routingProfile)
            let after = try rules(result.config)
            #expect(after.count == before.count)
            for (index, rule) in after.enumerated() {
                if let outbound = rule["outbound"] as? String { #expect(tags.contains(outbound), "rule \(index) dangles to \(outbound)") }
                if !result.applied.contains(index) {
                    #expect(NSDictionary(dictionary: rule) == NSDictionary(dictionary: before[index]), "rule \(index) changed without an override")
                }
            }
            for item in overrides.items where !result.applied.contains(item.ruleIndex) {
                #expect(result.stale.contains(item) || item.outbound == nil || before[item.ruleIndex]["outbound"] == nil)
            }
        }
        // A valid override is applied.
        let one = RouteOverrides(items: [RouteOverride(ruleIndex: 3, fingerprint: profile.rules[3].condition, outbound: "proxy", name: "视频")])
        let applied = RouteOverrides.apply(one, to: routingProfile)
        #expect(applied.applied == [3])
        #expect(try rules(applied.config)[3]["outbound"] as? String == "proxy")
        #expect(one.names(for: profile) == [3: "视频"])
        #expect(RouteOverrides.apply(RouteOverrides(), to: "not json").applied.isEmpty)
    }
}
