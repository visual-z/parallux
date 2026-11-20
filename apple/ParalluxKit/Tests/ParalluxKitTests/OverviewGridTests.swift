import Foundation
import Testing
@testable import ParalluxKit

private let gib: Int64 = 1 << 30

@Suite struct OverviewGridTests {
    /// The widths the overview really gets: the window's content area minus
    /// the page's margins, from the smallest window to a wide one.
    @Test func cardsShareARowOnlyWhileEachKeepsItsMinimumWidth() {
        let w = OverviewGrid.minimumCardWidth, s = OverviewGrid.spacing
        // Three cards.
        #expect(OverviewGrid.rows(count: 3, width: 3 * w + 2 * s) == [0..<3], "exactly enough for three")
        #expect(OverviewGrid.rows(count: 3, width: 3 * w + 2 * s - 1) == [0..<1, 1..<3], "one point short: the first card takes a row of its own")
        #expect(OverviewGrid.rows(count: 3, width: 2 * w + s) == [0..<1, 1..<3], "exactly enough for two")
        #expect(OverviewGrid.rows(count: 3, width: 2 * w + s - 1) == [0..<1, 1..<2, 2..<3], "one point short of two: a column")
        #expect(OverviewGrid.rows(count: 3, width: 2000) == [0..<3], "never more columns than cards")
        // The smallest window (760 pt, sidebar 200, margins 40) and the author's (937 pt).
        #expect(OverviewGrid.rows(count: 3, width: 520) == [0..<1, 1..<3])
        #expect(OverviewGrid.rows(count: 3, width: 677) == [0..<3])
        // Fewer cards (the others hidden).
        #expect(OverviewGrid.rows(count: 2, width: 520) == [0..<2])
        #expect(OverviewGrid.rows(count: 2, width: 2 * w + s - 1) == [0..<1, 1..<2])
        #expect(OverviewGrid.rows(count: 1, width: 520) == [0..<1])
        #expect(OverviewGrid.rows(count: 1, width: 10) == [0..<1], "a single card takes whatever there is")
        #expect(OverviewGrid.rows(count: 0, width: 520).isEmpty)
        // A width that is not a width.
        #expect(OverviewGrid.rows(count: 3, width: 0) == [0..<1, 1..<2, 2..<3])
        #expect(OverviewGrid.rows(count: 3, width: -5) == [0..<1, 1..<2, 2..<3])
        #expect(OverviewGrid.rows(count: 3, width: .nan) == [0..<1, 1..<2, 2..<3])
        #expect(OverviewGrid.rows(count: 3, width: .infinity) == [0..<3])
    }

    /// INV-15: for any number of cards and any width, the rows hold every
    /// card exactly once and in order, no card in a shared row is narrower
    /// than the minimum, and only the first row may be shorter than the rest.
    @Test func gridRowsCoverEveryCardOnceAndNeverSqueezeOne() {
        var rng = SplitMix64(seed: 0x0915)
        for _ in 0..<4000 {
            let count = rng.int(9) // 0 and 1 included
            let width = Double(rng.int(2400)) + Double(rng.int(100)) / 100
            let rows = OverviewGrid.rows(count: count, width: width)
            #expect(rows.flatMap { Array($0) } == Array(0..<count), "count \(count), width \(width): \(rows)")
            #expect(rows.allSatisfy { !$0.isEmpty })
            let widest = rows.map(\.count).max() ?? 0
            for (index, row) in rows.enumerated() {
                if row.count > 1 {
                    let each = (width - Double(row.count - 1) * OverviewGrid.spacing) / Double(row.count)
                    #expect(each >= OverviewGrid.minimumCardWidth, "count \(count), width \(width): a card of \(each) pt in \(rows)")
                }
                if index > 0 { #expect(row.count == widest, "only the first row may be short: \(rows)") }
            }
            // As many columns as fit: one more card in the widest row would squeeze.
            if widest < count {
                let each = (width - Double(widest) * OverviewGrid.spacing) / Double(widest + 1)
                #expect(!(each >= OverviewGrid.minimumCardWidth), "count \(count), width \(width): \(rows) wastes room for another column")
            }
        }
    }

    private func row(rule: String, outbound: String, type: String = "vless") -> ConnectionRow {
        var row = ConnectionRow(id: UUID().uuidString, process: "", destination: "example.com:443", rule: rule, outbound: outbound, chain: [outbound],
                                network: "tcp", uplinkTotal: 0, downlinkTotal: 0, createdAt: Date(timeIntervalSince1970: 0))
        row.outboundType = type
        return row
    }

    /// The route-mode card lays the most-hit rule out in rows; the parts
    /// say what the one-line sentence says.
    @Test func theMostHitRuleComesInPartsThatMakeTheSameSentence() throws {
        let connections = [
            row(rule: "rule_set=geosite-cn", outbound: "direct", type: "direct"),
            row(rule: "rule_set=geosite-cn", outbound: "direct", type: "direct"),
            row(rule: "domain_suffix=[example.org]", outbound: "DE-01"),
            row(rule: "", outbound: "Proxy"),
        ]
        let parts = try #require(OverviewCopy.topRuleParts(connections))
        #expect(parts == OverviewCopy.TopRule(rule: "geosite-cn", exit: "直连", share: 50))
        #expect(parts.route == "geosite-cn → 直连")
        #expect(parts.percent == "50%")
        #expect(OverviewCopy.topRule(connections) == "命中最多：\(parts.route)（\(parts.share)%）")
        // No rule was hit: no parts, no sentence.
        #expect(OverviewCopy.topRuleParts([row(rule: "", outbound: "Proxy")]) == nil)
        #expect(OverviewCopy.topRuleParts([]) == nil)
        #expect(OverviewCopy.topRule([]) == nil)
        // A hit without an exit name reads as the rule alone.
        #expect(OverviewCopy.TopRule(rule: "port=22", exit: "", share: 100).route == "port=22")
    }

    /// The profile card puts the usage label on one side and the figures on
    /// the other; together they are the sentence the card used to show.
    @Test func usageComesAsALabelAndFigures() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let utc = TimeZone(identifier: "UTC")!
        for usage in [SubscriptionUsage(upload: gib, download: 24 * gib, total: 100 * gib), SubscriptionUsage(upload: gib, download: gib), nil] {
            let summary = UsageSummary.make(usage: usage, sessionTotal: 3 * gib, now: now, timeZone: utc)
            #expect(summary.text == "\(summary.label) \(summary.value)")
            #expect(!summary.label.isEmpty && !summary.value.isEmpty)
            #expect(!summary.label.contains("/") && summary.value.contains(" / "), "the figures stay together: \(summary.label) | \(summary.value)")
        }
        let quota = UsageSummary.make(usage: SubscriptionUsage(upload: gib, download: 24 * gib, total: 100 * gib), sessionTotal: 0, now: now, timeZone: utc)
        #expect(quota.label == "已用")
        #expect(quota.value == "\(RateFormat.bytes(25 * gib)) / \(RateFormat.bytes(100 * gib))")
        let session = UsageSummary.make(usage: nil, sessionTotal: 3 * gib, now: now, timeZone: utc)
        #expect(session.label == "本次会话已用")
        #expect(session.value == "\(RateFormat.bytes(3 * gib)) / 无限")
    }
}
