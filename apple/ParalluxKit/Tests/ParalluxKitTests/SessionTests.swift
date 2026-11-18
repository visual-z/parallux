import Foundation
import Testing
@testable import ParalluxKit

@Suite struct RingBufferTests {
    @Test func aRingBufferKeepsTheNewestEntriesInOrder() {
        var rng = SplitMix64(seed: 0xB0FF)
        for capacity in [0, 1, 2, 7, 3000] {
            var buffer = RingBuffer<Int>(capacity: capacity)
            var reference: [Int] = []
            for value in 0..<(capacity * 3 + rng.int(50)) {
                buffer.append(value)
                reference.append(value)
                #expect(buffer.count <= capacity)
            }
            #expect(buffer.elements == Array(reference.suffix(capacity)), "capacity \(capacity)")
            buffer.removeAll()
            #expect(buffer.isEmpty)
            buffer.append(42)
            #expect(buffer.elements == (capacity == 0 ? [] : [42]))
        }
    }
}

@Suite struct LogQueryTests {
    @Test func logsFilterByLevelAndText() {
        #expect(LogLevel(sing: 0) == .panic)
        #expect(LogLevel(sing: 3) == .warn)
        #expect(LogLevel(sing: 6) == .trace)
        #expect(LogLevel(sing: 99) == .trace, "unknown levels are the least severe")
        let entries = [
            LogEntry(id: 1, level: .error, message: "dial tcp: Connection refused"),
            LogEntry(id: 2, level: .info, message: "inbound/tun: connection to example.com"),
            LogEntry(id: 3, level: .debug, message: "dns: exchange EXAMPLE.com"),
        ]
        #expect(LogQuery.filter(entries, level: .trace, text: "").map(\.id) == [1, 2, 3])
        #expect(LogQuery.filter(entries, level: .info, text: "").map(\.id) == [1, 2])
        #expect(LogQuery.filter(entries, level: .trace, text: "example").map(\.id) == [2, 3])
        #expect(LogQuery.filter(entries, level: .error, text: "refused").map(\.id) == [1])
        #expect(LogQuery.filter([], level: .trace, text: "x").isEmpty)
    }
}

@Suite struct DelayGradeTests {
    @Test func delaysAreGradedAtTheDesignThresholds() {
        #expect(DelayGrade(milliseconds: -1) == .untested)
        #expect(DelayGrade(milliseconds: 0) == .untested)
        #expect(DelayGrade(milliseconds: 1) == .fast)
        #expect(DelayGrade(milliseconds: 149) == .fast)
        #expect(DelayGrade(milliseconds: 150) == .slow)
        #expect(DelayGrade(milliseconds: .max) == .slow)
    }
}

@Suite struct RouteModeTests {
    @Test func routeModesAreTitledInChinese() {
        #expect(RouteMode.title("Rule") == "规则")
        #expect(RouteMode.title("rule") == "规则")
        #expect(RouteMode.title("GLOBAL") == "全局")
        #expect(RouteMode.title("Direct") == "直连")
        #expect(RouteMode.title("Streaming") == "Streaming")
        #expect(RouteMode.title("") == "")
    }
}

@Suite struct ConnectionQueryTests {
    @Test func connectionSearchMatchesEveryVisibleColumn() {
        let rows = [
            ConnectionRow(id: "1", process: "Safari", destination: "video.googlevideo.com:443", rule: "rule_set=geosite-youtube", outbound: "Proxy"),
            ConnectionRow(id: "2", process: "Steam", destination: "steamcdn-a.akamaihd.net:443", rule: "rule_set=geosite-steam@cn", outbound: "direct"),
            ConnectionRow(id: "3", process: "", destination: "1.1.1.1:53", rule: "protocol=dns", outbound: "dns-out"),
        ]
        #expect(ConnectionQuery.filter(rows, text: "").map(\.id) == ["1", "2", "3"])
        #expect(ConnectionQuery.filter(rows, text: "safari").map(\.id) == ["1"])
        #expect(ConnectionQuery.filter(rows, text: "AKAMAI").map(\.id) == ["2"])
        #expect(ConnectionQuery.filter(rows, text: "protocol=dns").map(\.id) == ["3"])
        #expect(ConnectionQuery.filter(rows, text: "direct").map(\.id) == ["2"])
        #expect(ConnectionQuery.filter(rows, text: "nothing").isEmpty)
    }
}

@Suite struct RuleSummaryTests {
    private let config = """
    {
      "route": {
        "rules": [
          { "action": "sniff" },
          { "protocol": "dns", "action": "hijack-dns" },
          { "rule_set": "geosite-cn", "outbound": "direct" },
          { "domain_suffix": ["a.com", "b.com", "c.com", "d.com"], "outbound": "Proxy", "parallux_future_field": 1 },
          { "type": "logical", "mode": "and", "rules": [ { "port": 443 }, { "network": "udp" } ], "action": "reject" }
        ],
        "final": "Proxy"
      }
    }
    """

    @Test func rulesAreListedFromTheProfileWithHitCounts() throws {
        let rules = RuleSummary.parse(config: config)
        try #require(rules.count == 5)
        #expect(rules.map(\.action) == ["sniff", "hijack-dns", "→ direct", "→ Proxy", "reject"])
        #expect(rules[2].condition.contains("geosite-cn"))
        #expect(rules[3].condition.contains("a.com"), "an unknown field does not drop the rule")
        let connections = [
            ConnectionRow(id: "1", process: "", destination: "", rule: "rule_set=geosite-cn", outbound: "direct"),
            ConnectionRow(id: "2", process: "", destination: "", rule: "rule_set=geosite-cn", outbound: "direct"),
            ConnectionRow(id: "3", process: "", destination: "", rule: "domain_suffix=[a.com b.com c.com...]", outbound: "Proxy"),
            ConnectionRow(id: "4", process: "", destination: "", rule: "", outbound: "Proxy"),
        ]
        let hits = RuleSummary.hits(rules, connections: connections)
        #expect(hits[2] == 2)
        #expect(hits[3] == 1)
        #expect(hits[0] == nil, "a rule without conditions never claims final-route connections")
        #expect(RuleSummary.parse(config: "not json").isEmpty)
        #expect(RuleSummary.parse(config: "{}").isEmpty)
    }
}
