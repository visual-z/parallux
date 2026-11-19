import Foundation
import Testing
@testable import ParalluxKit

/// docs/tasks/fix-overview-design-parity.md: the overview's flow diagram as
/// design v0.2 draws it (width = rate against a capacity, bands meeting on the
/// centre bar, particles), and the copy around it.
@Suite struct OverviewDesignTests {
    private let height = 262.0
    private let gap = 34.0

    @Test func aFlowLayoutWithCapacityIsProportionalAndNeverOverflows() {
        var rng = SplitMix64(seed: 0xF10)
        let rateChoices: [Double] = [0, 1, 95, 420, 1e9]
        let capacities: [Double] = [1, 500, 1000, 1e9, 4e9]
        for round in 0..<400 {
            // Rounds 0 and 1 pin the empty and single-node cases; 5 is the most
            // nodes a column shows (FlowSummary.maxExits + 1).
            let leftCount = round == 0 ? 0 : round == 1 ? 1 : rng.int(6)
            let rightCount = round == 0 ? 0 : round == 1 ? 1 : rng.int(6)
            let left = (0..<leftCount).map { _ in rateChoices[rng.int(rateChoices.count)] }
            let right = (0..<rightCount).map { _ in rateChoices[rng.int(rateChoices.count)] }
            let capacity = capacities[rng.int(capacities.count)]
            let layout = SankeyLayout.make(left: left, right: right, height: height, gap: gap, capacity: capacity)
            let context = Comment(rawValue: "round \(round): left \(left) right \(right) capacity \(capacity)")
            #expect(layout.left.count == left.count, context)
            #expect(layout.right.count == right.count, context)

            // Nothing leaves the drawing area, and neighbours keep room for their labels.
            for column in [layout.left, layout.right] {
                for span in column {
                    #expect(span.lower >= -1e-6 && span.upper <= height + 1e-6, context)
                }
                for (above, below) in zip(column, column.dropFirst()) {
                    #expect(below.lower - above.upper >= gap - 1e-6, context)
                }
            }

            let total = left.reduce(0, +)
            let rightTotal = right.reduce(0, +)
            if total == 0 || rightTotal == 0 {
                #expect(layout.bands.isEmpty, "no traffic, no bands")
                #expect(layout.total.length == 0, context)
                continue
            }

            // Width = rate: a rate is that share of the capacity, unless the
            // label gaps leave less room, in which case everything shrinks alike.
            let fit = (height - gap * Double(max(leftCount, rightCount) - 1)) / total
            let scale = min(height / capacity, fit)
            let tolerance = 1e-6 * max(1, total * scale)
            #expect(abs(layout.total.length - total * scale) <= tolerance, context)
            #expect(layout.total.lower >= -1e-6 && layout.total.upper <= height + 1e-6, context)
            for (index, node) in layout.left.enumerated() {
                #expect(abs(node.length - left[index] * scale) <= tolerance, context)
            }
            for (index, node) in layout.right.enumerated() {
                #expect(abs(node.length - right[index] * total / rightTotal * scale) <= tolerance, context)
            }

            // Every node is exactly as tall as the bands through it (INV-3 holds here too).
            for (index, node) in layout.left.enumerated() {
                let bands = layout.bands.filter { $0.from == index }
                #expect(abs(bands.map(\.left.length).reduce(0, +) - node.length) <= tolerance, context)
                for band in bands { #expect(band.left.lower >= node.lower - tolerance && band.left.upper <= node.upper + tolerance, context) }
            }
            for (index, node) in layout.right.enumerated() {
                let bands = layout.bands.filter { $0.to == index }
                #expect(abs(bands.map(\.right.length).reduce(0, +) - node.length) <= tolerance, context)
                for band in bands { #expect(band.right.lower >= node.lower - tolerance && band.right.upper <= node.upper + tolerance, context) }
            }

            // The centre bar is tiled by the bands, exit by exit and link by link
            // within an exit, and a band is equally thick at all three places.
            let ordered = layout.bands.sorted { ($0.to, $0.from) < ($1.to, $1.from) }
            var cursor = layout.total.lower
            for band in ordered {
                #expect(abs(band.center.lower - cursor) <= tolerance, context)
                #expect(abs(band.center.length - band.left.length) <= tolerance, context)
                #expect(abs(band.right.length - band.left.length) <= tolerance, context)
                cursor = band.center.upper
            }
            #expect(abs(cursor - layout.total.upper) <= tolerance, context)
        }
    }

    @Test func flowCapacityIsASteppedCeilingWithAFloor() {
        let floor = FlowScale.floor
        #expect(floor > 0)
        #expect(FlowScale.capacity(peak: 0) == floor)
        #expect(FlowScale.capacity(peak: -5) == floor)
        #expect(FlowScale.capacity(peak: 1) == floor)
        #expect(FlowScale.capacity(peak: floor) == floor, "a peak exactly on a step stays on it")
        #expect(FlowScale.capacity(peak: floor + 1) == 2 * floor)
        #expect(FlowScale.capacity(peak: 2 * floor + 1) == 5 * floor)
        #expect(FlowScale.capacity(peak: 5 * floor + 1) == 10 * floor)
        #expect(FlowScale.capacity(peak: Int64.max) == Int64.max, "the largest peak neither traps nor falls below itself")

        var rng = SplitMix64(seed: 0xCA9)
        var peaks: [Int64] = (0..<500).map { _ in Int64(rng.next() >> UInt64(1 + rng.int(62))) }
        peaks.sort()
        var previous: Int64 = 0
        for peak in peaks {
            let capacity = FlowScale.capacity(peak: peak)
            #expect(capacity >= peak && capacity >= floor, "peak \(peak) got \(capacity)")
            #expect(capacity >= previous, "capacity fell from \(previous) to \(capacity) as the peak rose to \(peak)")
            previous = capacity
            // Steps exist below the point where the next one would overflow.
            guard peak <= Int64.max / 10 else { continue }
            #expect(Double(capacity) <= max(Double(floor), Double(peak) * 2.5), "peak \(peak) got \(capacity)")
            var mantissa = capacity / floor
            #expect(capacity % floor == 0, "peak \(peak) got \(capacity)")
            // mantissa > 0: a capacity below the floor must fail above, not hang here.
            while mantissa > 0, mantissa % 10 == 0 { mantissa /= 10 }
            #expect([1, 2, 5].contains(mantissa), "peak \(peak) got \(capacity)")
        }
    }

    @Test func flowParticlesStayBoundedAndInsideTheirBands() throws {
        var rng = SplitMix64(seed: 0xD07)
        var particles = FlowParticles()
        let steps: [Double] = [0, 1.0 / 60, 1.0 / 30, 0.05, 5]
        let rateChoices: [Double] = [0, 1, 95, 420]
        var layout = SankeyLayout()
        var sawParticles = false
        for round in 0..<1500 {
            // Traffic changes every 40 steps; some phases have none at all.
            if round % 40 == 0 {
                let left = (0..<rng.int(4)).map { _ in rateChoices[rng.int(rateChoices.count)] }
                let right = (0..<rng.int(4)).map { _ in rateChoices[rng.int(rateChoices.count)] }
                layout = SankeyLayout.make(left: left, right: right, height: height, gap: gap, capacity: 1000)
            }
            particles.step(by: steps[rng.int(steps.count)], bands: layout.bands, using: &rng)
            #expect(particles.particles.count <= FlowParticles.limit)
            if layout.bands.isEmpty { #expect(particles.particles.isEmpty, "particles outlived their bands (round \(round))") }
            for particle in particles.particles {
                let band = try #require(layout.bands.first { $0.from == particle.from && $0.to == particle.to },
                                        "a particle belongs to no band (round \(round))")
                #expect(particle.progress >= 0 && particle.progress < 2)
                #expect(particle.lane >= 0 && particle.lane <= 1)
                let (start, end) = particle.progress < 1 ? (band.left, band.center) : (band.center, band.right)
                let y = FlowParticles.y(of: particle, in: band)
                #expect(y >= min(start.lower, end.lower) - 1e-6 && y <= max(start.upper, end.upper) + 1e-6,
                        "particle at \(y) left its band (round \(round))")
            }
            sawParticles = sawParticles || !particles.particles.isEmpty
        }
        #expect(sawParticles, "traffic never produced a particle")

        // Bands as thick as the whole diagram, for a long time: the count
        // reaches the limit's order of magnitude and never passes it.
        let full = SankeyLayout.make(left: [600, 400], right: [700, 300], height: height, gap: gap, capacity: 1)
        var saturated = FlowParticles()
        var most = 0
        for _ in 0..<2000 {
            saturated.step(by: 0.05, bands: full.bands, using: &rng)
            most = max(most, saturated.particles.count)
            #expect(saturated.particles.count <= FlowParticles.limit)
        }
        #expect(most > FlowParticles.limit / 4, "saturated bands only ever held \(most) particles")
    }

    @Test func flowSummaryCountsRewrittenDirectOutboundsAsDirect() {
        func row(_ id: String, outbound: String, type: String, up: Int64, down: Int64) -> ConnectionRow {
            var row = ConnectionRow(id: id, process: "", destination: "", rule: "", outbound: outbound)
            row.outboundType = type
            row.uplink = up
            row.downlink = down
            return row
        }
        // With two links or more the composer replaces the profile's direct
        // outbounds by aggregate outbounds of the same tag.
        let exits = FlowSummary.exits([
            row("1", outbound: "direct", type: "aggregate", up: 10, down: 90),
            row("2", outbound: "direct-cn", type: "aggregate", up: 0, down: 50),
            row("3", outbound: "HK-03", type: "hysteria2", up: 20, down: 400),
            row("4", outbound: "direct", type: "direct", up: 0, down: 5),
        ])
        #expect(exits == [.init(name: "HK-03", rate: 420), .init(name: FlowSummary.directName, rate: 155)])
    }

    @Test func overviewCopyFollowsTheDesign() {
        #expect(OverviewCopy.subtitle(links: 3, mode: .bond, server: "东京 VPS") == "3 条线路 · 叠加 · 经东京 VPS")
        #expect(OverviewCopy.subtitle(links: 2, mode: .bond, server: "Tokyo") == "2 条线路 · 叠加 · 经 Tokyo")
        #expect(OverviewCopy.subtitle(links: 2, mode: .bond, server: nil) == "2 条线路 · 叠加")
        #expect(OverviewCopy.subtitle(links: 2, mode: .balance, server: "东京 VPS") == "2 条线路 · 分流")
        #expect(OverviewCopy.subtitle(links: 2, mode: .failover, server: nil) == "2 条线路 · 主备")
        #expect(OverviewCopy.subtitle(links: 1, mode: nil, server: nil) == "1 条线路")
        #expect(OverviewCopy.subtitle(links: 0, mode: nil, server: nil) == "0 条线路")

        #expect(OverviewCopy.linkDetail(enabled: false, standby: false, rate: 500) == "已停用")
        #expect(OverviewCopy.linkDetail(enabled: true, standby: true, rate: 0) == "待命")
        #expect(OverviewCopy.linkDetail(enabled: true, standby: true, rate: 125_000) == "1.0 Mbps", "a link carrying traffic is not standing by")
        #expect(OverviewCopy.linkDetail(enabled: true, standby: false, rate: 0) == "0 bps")

        #expect(OverviewCopy.exitDetail(direct: true, mode: .bond, rate: 125_000) == "1.0 Mbps")
        #expect(OverviewCopy.exitDetail(direct: false, mode: .bond, rate: 56_750_000) == "叠加后转发 · 454 Mbps")
        #expect(OverviewCopy.exitDetail(direct: false, mode: .balance, rate: 125_000) == "按连接分到各线路 · 1.0 Mbps")
        #expect(OverviewCopy.exitDetail(direct: false, mode: .failover, rate: 0) == "仅主线路 · 0 bps")
        #expect(OverviewCopy.exitDetail(direct: false, mode: nil, rate: 125_000) == "1.0 Mbps")

        #expect(OverviewCopy.exitName(node: "HK-03", server: "东京 VPS", mode: .bond) == "东京 VPS → HK-03")
        #expect(OverviewCopy.exitName(node: "HK-03", server: "东京 VPS", mode: .balance) == "HK-03")
        #expect(OverviewCopy.exitName(node: "HK-03", server: nil, mode: .bond) == "HK-03")

        #expect(OverviewCopy.centre(mode: .bond, rate: 91_375_000) == "叠加 · 731 Mbps")
        #expect(OverviewCopy.centre(mode: nil, rate: 0) == "0 bps")
    }

    @Test func linkStandingFollowsModeOrderAndBackup() {
        let three = ["en7", "en0", "en8"]
        // 主备: the first link that is not backup-only leads, the rest wait.
        #expect(LinkStanding.all(enabled: three, backup: [], mode: .failover) == ["en7": .primary, "en0": .standby, "en8": .standby])
        #expect(LinkStanding.all(enabled: three, backup: ["en7"], mode: .failover) == ["en7": .standby, "en0": .primary, "en8": .standby])
        #expect(LinkStanding.all(enabled: three, backup: Set(three), mode: .failover) == ["en7": .primary, "en0": .standby, "en8": .standby],
                "with only backup links the first still carries the traffic")
        // 分流 and 叠加 use every link except the backup-only ones.
        for mode in [AggregationMode.balance, .bond] {
            #expect(LinkStanding.all(enabled: three, backup: [], mode: mode) == ["en7": .carrying, "en0": .carrying, "en8": .carrying])
            #expect(LinkStanding.all(enabled: three, backup: ["en8"], mode: mode) == ["en7": .carrying, "en0": .carrying, "en8": .standby])
            #expect(LinkStanding.all(enabled: three, backup: Set(three), mode: mode) == ["en7": .carrying, "en0": .standby, "en8": .standby])
        }
        // One link, or none: no aggregation mode is in effect.
        #expect(LinkStanding.all(enabled: ["en0"], backup: [], mode: nil) == ["en0": .carrying])
        #expect(LinkStanding.all(enabled: ["en0"], backup: ["en0"], mode: nil) == ["en0": .carrying])
        #expect(LinkStanding.all(enabled: [], backup: ["en0"], mode: .failover).isEmpty)
        // A link that is not in the enabled list has no entry: the caller shows it as disabled.
        #expect(LinkStanding.all(enabled: ["en0"], backup: [], mode: nil)["en7"] == nil)

        #expect(LinkStanding.primary.badge == "主")
        #expect(LinkStanding.standby.badge == "备")
        #expect(LinkStanding.carrying.badge == nil)
        #expect(LinkStanding.disabled.badge == nil)
    }

    // docs/tasks/fix-design-parity-followups.md

    @Test func overviewSubtitleGivesWayToAProblem() {
        #expect(OverviewCopy.subtitle(links: 2, mode: .bond, server: "东京 VPS", problem: "已连接，但读不到内核：EOF") == "已连接，但读不到内核：EOF")
        #expect(OverviewCopy.subtitle(links: 1, mode: nil, server: nil, problem: "配置读取失败") == "配置读取失败")
        #expect(OverviewCopy.subtitle(links: 2, mode: .bond, server: "东京 VPS", problem: nil) == "2 条线路 · 叠加 · 经东京 VPS")
        #expect(OverviewCopy.subtitle(links: 2, mode: .failover, server: nil, problem: "") == "2 条线路 · 主备", "an empty problem is no problem")
    }

    @Test func linkStandingFollowsTheCoresLinkOrder() {
        let three = ["en7", "en0", "en8"]
        // 主备: the lead is the first healthy primary, then the first healthy backup, then simply the first.
        #expect(LinkStanding.all(enabled: three, backup: [], unhealthy: ["en7"], mode: .failover) == ["en7": .standby, "en0": .primary, "en8": .standby])
        #expect(LinkStanding.all(enabled: three, backup: ["en8"], unhealthy: ["en7", "en0"], mode: .failover) == ["en7": .standby, "en0": .standby, "en8": .primary])
        #expect(LinkStanding.all(enabled: three, backup: [], unhealthy: Set(three), mode: .failover) == ["en7": .primary, "en0": .standby, "en8": .standby])
        // 分流 and 叠加: every healthy primary carries; without one, a single link is picked as 主备 would.
        for mode in [AggregationMode.balance, .bond] {
            #expect(LinkStanding.all(enabled: three, backup: [], unhealthy: ["en0"], mode: mode) == ["en7": .carrying, "en0": .standby, "en8": .carrying])
            #expect(LinkStanding.all(enabled: three, backup: ["en8"], unhealthy: ["en7", "en0"], mode: mode) == ["en7": .standby, "en0": .standby, "en8": .carrying])
            #expect(LinkStanding.all(enabled: three, backup: [], unhealthy: Set(three), mode: mode) == ["en7": .carrying, "en0": .standby, "en8": .standby])
        }
        // One link is what it is, healthy or not; an unknown name in `unhealthy` changes nothing.
        #expect(LinkStanding.all(enabled: ["en0"], backup: [], unhealthy: ["en0"], mode: nil) == ["en0": .carrying])
        #expect(LinkStanding.all(enabled: three, backup: [], unhealthy: ["en9"], mode: .failover)
            == LinkStanding.all(enabled: three, backup: [], mode: .failover))
        #expect(LinkStanding.all(enabled: [], backup: [], unhealthy: ["en0"], mode: .failover).isEmpty)
    }

    @Test func topRuleNamesTheMostHitRuleAndItsShare() {
        func row(_ id: Int, rule: String, outbound: String, type: String) -> ConnectionRow {
            var row = ConnectionRow(id: "\(id)", process: "", destination: "", rule: rule, outbound: outbound)
            row.outboundType = type
            return row
        }
        #expect(OverviewCopy.topRule([]) == nil)
        #expect(OverviewCopy.topRule([row(0, rule: "", outbound: "Proxy", type: "selector")]) == nil, "route.final is not a rule")

        // 61 of 100 connections hit geosite-cn; most of those left directly.
        var rows = (0..<58).map { row($0, rule: "rule_set=geosite-cn", outbound: "direct", type: "direct") }
        rows += (58..<61).map { row($0, rule: "rule_set=geosite-cn", outbound: "CN-relay", type: "vmess") }
        rows += (61..<90).map { row($0, rule: "rule_set=[geosite-youtube geosite-github]", outbound: "Proxy", type: "selector") }
        rows += (90..<100).map { row($0, rule: "", outbound: "Proxy", type: "selector") }
        #expect(OverviewCopy.topRule(rows) == "命中最多：geosite-cn → 直连（61%）")

        // A rewritten direct outbound (two links or more) is still 直连; other items keep their key.
        #expect(OverviewCopy.topRule([row(0, rule: "rule_set=geosite-cn", outbound: "direct", type: "aggregate")]) == "命中最多：geosite-cn → 直连（100%）")
        #expect(OverviewCopy.topRule([row(0, rule: "protocol=dns", outbound: "dns-out", type: "dns"), row(1, rule: "", outbound: "Proxy", type: "selector")])
            == "命中最多：protocol=dns → dns-out（50%）")
        #expect(OverviewCopy.topRule([row(0, rule: "rule_set=[geosite-a geosite-b]", outbound: "Proxy", type: "selector")])
            == "命中最多：rule_set=[geosite-a geosite-b] → Proxy（100%）")

        // A tie goes to the smaller rule text, whatever order the connections arrive in.
        let tie = [row(0, rule: "rule_set=geosite-b", outbound: "Proxy", type: "selector"), row(1, rule: "rule_set=geosite-a", outbound: "Proxy", type: "selector")]
        #expect(OverviewCopy.topRule(tie) == "命中最多：geosite-a → Proxy（50%）")
        #expect(OverviewCopy.topRule(tie.reversed()) == "命中最多：geosite-a → Proxy（50%）")
    }

    @Test func topRuleOmitsAnExitItDoesNotKnow() {
        // A connection the core reports without an outbound must not print 「→ （100%）」.
        let row = ConnectionRow(id: "1", process: "", destination: "", rule: "rule_set=geosite-cn", outbound: "")
        #expect(OverviewCopy.topRule([row]) == "命中最多：geosite-cn（100%）")
    }

    // docs/tasks/perf-flow-animation.md

    @Test func flowEaseIsFrameRateIndependentAndLandsExactly() throws {
        var rng = SplitMix64(seed: 0xEA5E)
        let choices: [Double] = [0, 1, 95, 420, 1e9]
        func rates(_ count: Int) -> [Double] { (0..<count).map { _ in choices[rng.int(choices.count)] } }
        #expect(FlowEase.duration > 0)

        // Empty: nothing to ease, nothing to wait for.
        var empty = FlowEase()
        empty.retarget([])
        #expect(empty.value.isEmpty)
        #expect(empty.isSettled)

        // The first target is taken as it is: there is nothing to come from.
        var first = FlowEase()
        first.retarget([7])
        #expect(first.value == [7])
        #expect(first.isSettled)

        for round in 0..<300 {
            let count = 1 + rng.int(5)
            let from = rates(count), to = rates(count)
            var ease = FlowEase()
            ease.retarget(from)
            ease.retarget(to)
            #expect(ease.value == from, "retargeting must not jump (round \(round))")
            #expect(ease.isSettled == (from == to))

            // The same time in one step, or in many uneven ones, ends in the same place.
            let time = FlowEase.duration * Double(rng.int(101)) / 100
            var once = ease
            once.advance(by: time)
            var many = ease
            var left = time
            while left > 0 {
                let step = min(left, FlowEase.duration * Double(1 + rng.int(20)) / 200)
                many.advance(by: step)
                left -= step
                // Never outside the two ends, at any point on the way. (#require:
                // a wrong count must fail here, not trap on the subscripts below.)
                try #require(many.value.count == count, "the eased value lost or gained nodes (round \(round))")
                for (index, value) in many.value.enumerated() {
                    #expect(value >= min(from[index], to[index]) && value <= max(from[index], to[index]), "overshoot (round \(round))")
                }
            }
            for (a, b) in zip(once.value, many.value) {
                #expect(abs(a - b) <= 1e-9 * max(1, abs(a)), "\(a) in one step, \(b) in many (round \(round))")
            }

            // A changed target carries on from where the value is.
            let mid = once.value
            let next = rates(count)
            once.retarget(next)
            #expect(once.value == mid, "a new target must continue from the current value (round \(round))")

            // The full duration lands on the target exactly; more time changes nothing.
            once.advance(by: FlowEase.duration)
            #expect(once.value == next)
            #expect(once.isSettled)
            once.advance(by: 1000)
            #expect(once.value == next)

            // Odd steps are harmless, and finish() lands at once.
            var odd = ease
            for step in [0, -1, Double.nan, -Double.infinity] { odd.advance(by: step) }
            #expect(odd.value == from, "a zero, negative or NaN step must not move anything")
            odd.advance(by: .infinity)
            #expect(odd.value == to)
            var cut = ease
            cut.finish()
            #expect(cut.value == to)
            #expect(cut.isSettled)

            // A different number of nodes cannot be eased: take the new values.
            var resized = ease
            resized.advance(by: time)
            let other = rates(count + 1)
            resized.retarget(other)
            #expect(resized.value == other)
            #expect(resized.isSettled)
        }

        // Halfway through, an ease-out has covered more than half the distance and less than all of it.
        var half = FlowEase()
        half.retarget([0])
        half.retarget([100])
        half.advance(by: FlowEase.duration / 2)
        let halfway = try #require(half.value.first)
        #expect(halfway > 50 && halfway < 100)
        #expect(!half.isSettled)
    }
}
