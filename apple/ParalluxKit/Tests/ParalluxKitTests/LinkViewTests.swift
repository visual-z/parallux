import Foundation
@testable import ParalluxKit
import Testing

@Suite struct LinkViewTests {
    typealias C = InterfaceRates.Counter

    @Test func interfaceRatesAreNeverNegativeAndKeyedByLinkTag() {
        let before = ["en0": C(received: 1000, sent: 100), "en7": C(received: 5000, sent: 500)]
        let after = ["en0": C(received: 3000, sent: 300), "en7": C(received: 9000, sent: 900), "en9": C(received: 77, sent: 77)]
        let rates = InterfaceRates.rates(previous: before, current: after, interval: 2)
        #expect(rates["link-en0"] == .init(upload: 100, download: 1000))
        #expect(rates["link-en7"] == .init(upload: 200, download: 2000))
        #expect(rates["link-en9"] == .init(upload: 0, download: 0), "new interface")
        #expect(rates["en0"] == nil, "keyed by link tag")
        #expect(InterfaceRates.rates(previous: before, current: after, interval: 0).isEmpty)
        #expect(InterfaceRates.rates(previous: before, current: after, interval: -1).isEmpty)
        #expect(InterfaceRates.rates(previous: [:], current: [:], interval: 1).isEmpty)
        // Past 2^32: 64-bit counters keep counting.
        let big = UInt64(1) << 33
        let wide = InterfaceRates.rates(previous: ["en0": C(received: big, sent: big)], current: ["en0": C(received: big + 4096, sent: big + 1)], interval: 1)
        #expect(wide["link-en0"] == .init(upload: 1, download: 4096))
        // Property: any two samples, never negative.
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next() -> UInt64 { seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; return seed }
        for _ in 0..<500 {
            let a = ["en0": C(received: next() % 1_000_000, sent: next() % 1_000_000)]
            let b = ["en0": C(received: next() % 1_000_000, sent: next() % 1_000_000)]
            let r = InterfaceRates.rates(previous: a, current: b, interval: Double(next() % 5 + 1))
            #expect((r["link-en0"]?.upload ?? 0) >= 0 && (r["link-en0"]?.download ?? 0) >= 0)
        }
        // The extreme: a counter at UInt64.max going back to 0 is a reset, not a huge rate.
        let reset = InterfaceRates.rates(previous: ["en0": C(received: .max, sent: .max)], current: ["en0": C(received: 0, sent: 0)], interval: 1)
        #expect(reset["link-en0"] == .init(upload: 0, download: 0))
    }

    static func link(_ tag: String, healthy: Bool, active: Int64) -> LinkGroupStat.Link {
        .init(tag: tag, healthy: healthy, backup: false, upload: 0, download: 0, active: active)
    }

    @Test func mergedLinkHealthIgnoresGroupOrder() {
        #expect(LinkView.merge([]).isEmpty)
        let groups = [
            LinkGroupStat(tag: "direct", mode: "balance", links: [Self.link("link-en0", healthy: true, active: 2), Self.link("link-en7", healthy: true, active: 1)]),
            LinkGroupStat(tag: "parallux-links", mode: "balance", links: [Self.link("link-en0", healthy: false, active: 3), Self.link("link-en7", healthy: true, active: 0)]),
            LinkGroupStat(tag: "direct-cn", mode: "balance", links: [Self.link("link-en7", healthy: true, active: 4)]),
        ]
        let expected: [String: LinkView.State] = ["link-en0": .init(healthy: false, active: 5), "link-en7": .init(healthy: true, active: 5)]
        func permutations<T>(_ items: [T]) -> [[T]] {
            guard items.count > 1 else { return [items] }
            return items.indices.flatMap { i -> [[T]] in
                var rest = items
                let head = rest.remove(at: i)
                return permutations(rest).map { [head] + $0 }
            }
        }
        for order in permutations(groups) {
            #expect(LinkView.merge(order) == expected)
        }
        #expect(LinkView.merge([groups[2]]) == ["link-en7": .init(healthy: true, active: 4)])
    }

    @Test func aggregateOutboundsCountAsDirect() {
        var row = ConnectionRow(id: "1", process: "", destination: "", rule: "", outbound: "direct")
        row.outboundType = "aggregate"
        row.downlink = 100
        #expect(FlowSummary.exits([row]) == [.init(name: FlowSummary.directName, rate: 100)])
    }

    @Test func theFlowDiagramHoldsThroughIdleSeconds() {
        let t0 = Date(timeIntervalSince1970: 1000)
        #expect(FlowHold.limit > 0)
        var state = FlowHold.next(current: [1, 2], last: [Int](), lastAt: nil, now: t0)
        #expect(state.shown == [1, 2])
        state = FlowHold.next(current: [Int](), last: state.last, lastAt: state.lastAt, now: t0.addingTimeInterval(1))
        #expect(state.shown == [1, 2], "an idle second keeps the last one")
        let atLimit = FlowHold.next(current: [Int](), last: [1, 2], lastAt: t0, now: t0.addingTimeInterval(FlowHold.limit))
        #expect(atLimit.shown == [1, 2])
        let past = FlowHold.next(current: [Int](), last: [1, 2], lastAt: t0, now: t0.addingTimeInterval(FlowHold.limit + 0.001))
        #expect(past.shown.isEmpty)
        let fresh = FlowHold.next(current: [3], last: [1, 2], lastAt: t0, now: t0.addingTimeInterval(100))
        #expect(fresh.shown == [3] && fresh.last == [3])
        #expect(FlowHold.next(current: [Int](), last: [Int](), lastAt: nil, now: t0).shown.isEmpty)
    }

    /// With 代理 off, direct traffic is bonded too, so the
    /// only reason left to run 叠加 as 主备 is a missing server.
    @Test func aggregationOnlyBondRunsAsBond() {
        #expect(AggregationNotice.text(chosen: .bond, effective: .bond) == nil)
        #expect(AggregationNotice.text(chosen: .bond, effective: .failover) == "尚未设置聚合服务器，暂按主备运行")
        #expect(AggregationNotice.text(chosen: .balance, effective: .balance) == nil)
        #expect(AggregationNotice.text(chosen: .bond, effective: nil) == nil)
        #expect(ProfileComposer.bondCarriesDirect, "direct aggregates take the bond")
    }
}
