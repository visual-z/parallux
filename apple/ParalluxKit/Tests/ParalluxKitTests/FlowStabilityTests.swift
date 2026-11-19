import Foundation
import Testing
@testable import ParalluxKit

/// docs/tasks/fix-flow-stability.md: nodes that keep their place, rates that
/// do not twitch, widths by share.
@Suite struct FlowStabilityTests {
    private func ids(_ slots: FlowSlots) -> [String] { slots.slots.map(\.id) }

    @Test func flowSlotsKeepTheirPlaceWhileTrafficComesAndGoes() throws {
        #expect(FlowSlots.retention > 0)
        var empty = FlowSlots(limit: 4)
        empty.update([], at: 0)
        #expect(empty.slots.isEmpty)

        // One node arrives, stays through idle seconds, and leaves only after the retention.
        var one = FlowSlots(limit: 4)
        one.update([("a", 100)], at: 0)
        #expect(ids(one) == ["a"])
        one.update([], at: FlowSlots.retention)
        #expect(ids(one) == ["a"], "idle for exactly the retention: still shown")
        one.update([], at: FlowSlots.retention + 0.001)
        #expect(one.slots.isEmpty, "idle past the retention: gone")

        // New nodes go behind the ones already shown, whatever their rates.
        var slots = FlowSlots(limit: 4)
        slots.update([("a", 10), ("b", 500)], at: 0)
        #expect(ids(slots) == ["a", "b"], "first seen, first placed: not by rate")
        slots.update([("c", 9000), ("b", 1), ("a", 1)], at: 1)
        #expect(ids(slots) == ["a", "b", "c"])
        slots.update([("c", 1)], at: 2)
        #expect(ids(slots) == ["a", "b", "c"], "a and b are idle, not gone")

        // Past the limit: the longest-idle node makes room first; if none is idle, the smallest joins 其他, which is last.
        slots.update([("c", 1), ("d", 5), ("e", 7)], at: 3)
        #expect(ids(slots) == ["b", "c", "d", "e"], "a was idle longest")
        slots.update([("b", 50), ("c", 40), ("d", 30), ("e", 20), ("f", 10)], at: 4)
        let crowded = slots.slots
        #expect(crowded.count == 5)
        #expect(crowded.last?.isOther == true)
        #expect(crowded.last?.id == FlowSlots.otherID)
        #expect(crowded.filter(\.isOther).count == 1)
        #expect(crowded.dropLast().map(\.id) == ["b", "c", "d", "e"])
        #expect((crowded.last?.rate ?? 0) > 0, "f's traffic is counted in 其他")

        // Property: over random arrivals and departures, survivors never swap places and the count stays bounded.
        var rng = SplitMix64(seed: 0x57AB)
        let names = ["a", "b", "c", "d", "e", "f", "g", "h"]
        for limit in [1, 2, 4] {
            var state = FlowSlots(limit: limit)
            var previous: [String] = []
            var lastSeen: [String: Double] = [:]
            for step in 0..<600 {
                let time = Double(step) * (step % 7 == 0 ? 2.5 : 1)
                let present = names.filter { _ in rng.int(4) == 0 }.map { (id: $0, rate: Double(1 + rng.int(1000))) }
                state.update(present, at: time)
                for item in present { lastSeen[item.id] = time }
                let shown = state.slots
                #expect(shown.filter { !$0.isOther }.count <= limit, "limit \(limit), step \(step)")
                #expect(shown.filter(\.isOther).count <= 1)
                if let other = shown.firstIndex(where: \.isOther) { #expect(other == shown.count - 1, "其他 is last") }
                #expect(Set(shown.map(\.id)).count == shown.count, "no node twice")
                let current = shown.filter { !$0.isOther }.map(\.id)
                // Survivors keep their relative order.
                let kept = previous.filter(current.contains)
                #expect(current.filter(previous.contains) == kept, "survivors swapped places at step \(step): \(previous) -> \(current)")
                // Nobody stays past the retention, and (with room) nobody leaves before it.
                for id in current {
                    let seen = try #require(lastSeen[id], "a node appeared that never had traffic")
                    #expect(time - seen <= FlowSlots.retention + 1e-9, "\(id) outstayed the retention at step \(step)")
                }
                if current.count < limit {
                    for id in previous where !current.contains(id) {
                        #expect(time - (lastSeen[id] ?? 0) > FlowSlots.retention, "\(id) left early at step \(step) although there was room")
                    }
                }
                for slot in shown { #expect(slot.rate.isFinite && slot.rate >= 0) }
                previous = current
            }
        }
    }

    @Test func flowSlotsSmoothRatesWithoutLag() throws {
        // A steady input is nearly reached within five updates and never overshot.
        var steady = FlowSlots(limit: 4)
        var last = 0.0
        for second in 0..<5 {
            steady.update([("a", 1000)], at: Double(second))
            let rate = try #require(steady.slots.first?.rate)
            #expect(rate <= 1000 + 1e-9, "overshoot at second \(second)")
            #expect(rate >= last, "a steady input must not sag")
            last = rate
        }
        #expect(last >= 900, "after five seconds the shown rate is \(last) of 1000")
        #expect((steady.slots.first?.rate ?? 0) > 0)

        // After the traffic stops the shown rate only falls.
        var falling = last
        for second in 5..<12 {
            steady.update([], at: Double(second))
            let rate = try #require(steady.slots.first?.rate)
            #expect(rate <= falling + 1e-9)
            falling = rate
        }
        #expect(falling < 100, "seven idle seconds later the shown rate is still \(falling)")

        // One second at a hundred times the usual rate does not take over the picture.
        var spiky = FlowSlots(limit: 4)
        for second in 0..<6 { spiky.update([("a", 100)], at: Double(second)) }
        spiky.update([("a", 10_000)], at: 6)
        #expect((spiky.slots.first?.rate ?? 0) <= 5000, "a one-second spike showed as \(spiky.slots.first?.rate ?? 0)")

        // The first sample of a new node is shown as it is: no ramp from zero for something that just appeared.
        var fresh = FlowSlots(limit: 4)
        fresh.update([("a", 640)], at: 0)
        #expect(fresh.slots.first?.rate == 640)

        // Odd input is harmless.
        var odd = FlowSlots(limit: 4)
        odd.update([("a", .nan), ("b", -5), ("c", .infinity), ("a", 7)], at: 0)
        for slot in odd.slots { #expect(slot.rate.isFinite && slot.rate >= 0) }
        odd.update([("a", 1)], at: -100)
        for slot in odd.slots { #expect(slot.rate.isFinite && slot.rate >= 0) }
    }

    @Test func theRecordedFlowIsSteadyAfterSmoothing() throws {
        let seconds = FlowRecording.seconds
        try #require(seconds.count == 120)
        // What the app showed: FlowSummary's snapshot each second.
        var rawMembership = 0, rawOrder = 0
        var before: [String] = []
        for (index, exits) in seconds.enumerated() {
            let now = exits.map(\.name)
            if index > 0 {
                if Set(now) != Set(before) { rawMembership += 1 }
                if now.filter(before.contains) != before.filter(now.contains) { rawOrder += 1 }
            }
            before = now
        }
        #expect(rawMembership == 85 && rawOrder == 34, "the fixture is not the recording the card describes: \(rawMembership), \(rawOrder)")

        var slots = FlowSlots(limit: FlowSummary.maxExits)
        var membership = 0, order = 0
        var previous: [String] = []
        for (index, exits) in seconds.enumerated() {
            // 其他 in the recording is already a merge; it is not a node of its own.
            let named = exits.filter { $0.name != FlowSummary.otherName }.map { (id: $0.name, rate: $0.rate) }
            slots.update(named, at: Double(index))
            let shown = slots.slots.filter { !$0.isOther }.map(\.id)
            if index > 0 {
                if Set(shown) != Set(previous) { membership += 1 }
                if shown.filter(previous.contains) != previous.filter(shown.contains) { order += 1 }
            }
            // Everything with traffic this second is in the picture, by name or inside 其他.
            let hasOther = slots.slots.contains(where: \.isOther)
            for item in named where item.rate > 0 {
                #expect(shown.contains(item.id) || hasOther, "\(item.id) had traffic at second \(index) and is nowhere")
            }
            previous = shown
        }
        #expect(order == 0, "survivors swapped places \(order) times")
        #expect(membership <= rawMembership / 4, "the set of exits still changed on \(membership) of 119 steps (raw: \(rawMembership))")
    }

    @Test func shareLayoutFillsTheHeightAndIgnoresAbsoluteRates() throws {
        let height = 262.0, gap = 34.0
        #expect(SankeyLayout.thinnestShare > 0 && SankeyLayout.thinnestShare < 0.2)
        var rng = SplitMix64(seed: 0x5A4E)
        let choices: [Double] = [0, 1, 95, 420, 1e9]

        // No traffic on a side: no bands, nodes still placed.
        let idle = SankeyLayout.make(leftShares: [0, 0], rightShares: [5], height: height, gap: gap)
        #expect(idle.bands.isEmpty)
        #expect(idle.left.count == 2 && idle.right.count == 1)
        #expect(SankeyLayout.make(leftShares: [], rightShares: [], height: height, gap: gap).bands.isEmpty)

        for round in 0..<300 {
            let left = (0..<(1 + rng.int(4))).map { _ in choices[rng.int(choices.count)] }
            let right = (0..<(1 + rng.int(5))).map { _ in choices[rng.int(choices.count)] }
            let layout = SankeyLayout.make(leftShares: left, rightShares: right, height: height, gap: gap)
            let context = Comment(rawValue: "round \(round): left \(left) right \(right)")
            try #require(layout.left.count == left.count && layout.right.count == right.count, context)
            let leftTotal = left.reduce(0, +), rightTotal = right.reduce(0, +)
            if leftTotal == 0 || rightTotal == 0 {
                #expect(layout.bands.isEmpty, context)
                continue
            }
            // Both sides are equally tall and as tall as the gaps allow: the picture is always full.
            let room = height - gap * Double(max(left.count, right.count) - 1)
            let leftSum = layout.left.map(\.length).reduce(0, +), rightSum = layout.right.map(\.length).reduce(0, +)
            #expect(abs(leftSum - room) <= 1e-6 * room, "left fills \(leftSum) of \(room) (\(context))")
            #expect(abs(rightSum - room) <= 1e-6 * room, context)
            #expect(abs(layout.total.length - room) <= 1e-6 * room, context)
            for column in [layout.left, layout.right] {
                for span in column { #expect(span.lower >= -1e-6 && span.upper <= height + 1e-6, context) }
                for (above, below) in zip(column, column.dropFirst()) { #expect(below.lower - above.upper >= gap - 1e-6, context) }
            }
            // A node with traffic is never thinner than the floor; one without is flat.
            for (rates, column) in [(left, layout.left), (right, layout.right)] {
                for (rate, span) in zip(rates, column) {
                    if rate > 0 { #expect(span.length >= SankeyLayout.thinnestShare * room - 1e-6, context) } else { #expect(span.length <= 1e-9, context) }
                }
                // Order is kept: a larger rate is never drawn thinner than a smaller one on the same side.
                for (i, a) in rates.enumerated() {
                    for (j, b) in rates.enumerated() where a > b { #expect(column[i].length >= column[j].length - 1e-6, context) }
                }
            }
            // INV-3: every node is as tall as the bands through it, and the bar is tiled.
            for (index, node) in layout.left.enumerated() {
                #expect(abs(layout.bands.filter { $0.from == index }.map(\.left.length).reduce(0, +) - node.length) <= 1e-6 * room, context)
            }
            for (index, node) in layout.right.enumerated() {
                #expect(abs(layout.bands.filter { $0.to == index }.map(\.right.length).reduce(0, +) - node.length) <= 1e-6 * room, context)
            }
            #expect(abs(layout.bands.map(\.center.length).reduce(0, +) - layout.total.length) <= 1e-6 * room, context)

            // Only shares matter: scale either side by anything and nothing moves.
            let scaled = SankeyLayout.make(leftShares: left.map { $0 * 1e-6 }, rightShares: right.map { $0 * 37 }, height: height, gap: gap)
            for (a, b) in zip(layout.left + layout.right, scaled.left + scaled.right) {
                #expect(abs(a.lower - b.lower) <= 1e-6 * height && abs(a.upper - b.upper) <= 1e-6 * height, context)
            }
        }

        // Shares, concretely: 3 : 1 on the left of a two-node side with one exit.
        let layout = SankeyLayout.make(leftShares: [300, 100], rightShares: [8], height: 100, gap: 20)
        #expect(abs(layout.left[0].length - 60) < 1e-6 && abs(layout.left[1].length - 20) < 1e-6)
        #expect(abs(layout.right[0].length - 80) < 1e-6)
    }

    @Test func routeRowsKeepProfileOrderAndOnlyMoveAfterRetention() {
        let order = ["r1", "r2", "r3", "r4", "final"]
        var rows = RouteRows()
        rows.update(order: order, rates: [:], at: 0)
        #expect(rows.active.isEmpty)
        #expect(rows.idle == order, "nothing has traffic: the profile's order")

        // Traffic moves a row up into the active section; both sections stay in profile order whatever the rates.
        rows.update(order: order, rates: ["r3": 5, "final": 9000, "r1": 1], at: 1)
        #expect(rows.active == ["r1", "r3", "final"])
        #expect(rows.idle == ["r2", "r4"])
        rows.update(order: order, rates: ["r3": 99_999, "final": 1, "r1": 50], at: 2)
        #expect(rows.active == ["r1", "r3", "final"], "rates changed, rows must not move")

        // A row that falls silent stays where it is until the retention has passed.
        rows.update(order: order, rates: ["final": 1], at: 3)
        #expect(rows.active == ["r1", "r3", "final"])
        rows.update(order: order, rates: ["final": 1], at: 2 + FlowSlots.retention)
        #expect(rows.active == ["r1", "r3", "final"], "idle for exactly the retention")
        rows.update(order: order, rates: ["final": 1], at: 2 + FlowSlots.retention + 0.5)
        #expect(rows.active == ["final"])
        #expect(rows.idle == ["r1", "r2", "r3", "r4"])

        // Rules that left the profile leave the rows; new ones appear in the profile's place.
        rows.update(order: ["r0", "r2", "final"], rates: ["r2": 3, "final": 1], at: 40)
        #expect(rows.active == ["r2", "final"])
        #expect(rows.idle == ["r0"])
        rows.update(order: [], rates: ["r2": 3], at: 41)
        #expect(rows.active.isEmpty && rows.idle.isEmpty)
    }

    @Test func particleDensityFollowsTheAbsoluteRate() {
        // Widths are shares now, so how busy the dots are is what tells a trickle from a download.
        #expect(FlowParticles.intensity(bytesPerSecond: 0) == 0, "no traffic, no dots")
        #expect(FlowParticles.intensity(bytesPerSecond: -5) == 0)
        #expect(FlowParticles.intensity(bytesPerSecond: .nan) == 0)
        let trickle = FlowParticles.intensity(bytesPerSecond: 1)
        #expect(trickle > 0 && trickle <= 0.2, "any traffic shows a few dots: \(trickle)")
        #expect(FlowParticles.intensity(bytesPerSecond: 1e12) == 1)
        #expect(FlowParticles.intensity(bytesPerSecond: 12_500_000) == 1, "100 Mbit/s is the full picture")
        var previous = 0.0
        for exponent in stride(from: 0.0, through: 9, by: 0.25) {
            let value = FlowParticles.intensity(bytesPerSecond: pow(10, exponent))
            #expect(value >= previous && value <= 1, "not monotone at 1e\(exponent)")
            previous = value
        }
        // A thousand times the traffic is clearly busier, not a thousand times as many dots.
        let slow = FlowParticles.intensity(bytesPerSecond: 12_500), fast = FlowParticles.intensity(bytesPerSecond: 12_500_000)
        #expect(fast / slow >= 3 && fast / slow <= 20, "100 Kbit/s \(slow) against 100 Mbit/s \(fast)")

        // The spawn rate follows it: half the intensity, about half the dots.
        var rng = SplitMix64(seed: 0xD075)
        let layout = SankeyLayout.make(leftShares: [1], rightShares: [1], height: 262, gap: 34)
        var full = FlowParticles(), half = FlowParticles(), none = FlowParticles()
        for _ in 0..<600 {
            full.step(by: 1.0 / 60, bands: layout.bands, intensity: 1, using: &rng)
            half.step(by: 1.0 / 60, bands: layout.bands, intensity: 0.5, using: &rng)
            none.step(by: 1.0 / 60, bands: layout.bands, intensity: 0, using: &rng)
        }
        #expect(none.particles.isEmpty)
        let ratio = Double(half.particles.count) / Double(max(full.particles.count, 1))
        #expect(ratio > 0.35 && ratio < 0.65, "half the intensity gave \(half.particles.count) of \(full.particles.count) dots")
    }
}

/// docs/tasks/fix-ui-details.md
@Suite struct UIDetailTests {
    @Test func actionFailuresSayWhatFailedNotThatTheCoreIsGone() {
        #expect(CoreAction.urlTest.failure == "延迟测试失败")
        #expect(CoreAction.selectOutbound.failure == "切换节点失败")
        #expect(CoreAction.setRouteMode.failure == "切换路由模式失败")
        #expect(CoreAction.closeConnection.failure == "关闭连接失败")
        #expect(CoreAction.clearLogs.failure == "清除日志失败")
        let all = CoreAction.allCases.map(\.failure)
        #expect(Set(all).count == all.count, "every action has its own sentence")
        for text in all {
            #expect(!text.isEmpty && text.count <= 12, "short enough for a subtitle: \(text)")
            #expect(!text.contains("内核") && !text.contains("rpc") && !text.contains(":"))
        }
        // Shown as the status line's action error: as it is, not as a core the app cannot read.
        let line = StatusLine.text(setup: .ready, tunnel: .connected, actionError: CoreAction.urlTest.failure, coreError: nil, linkKind: "Wi‑Fi")
        #expect(line == "延迟测试失败")
        #expect(!line.contains("读不到内核"))
        // A core that really cannot be read still says so.
        #expect(StatusLine.text(setup: .ready, tunnel: .connected, actionError: nil, coreError: "EOF", linkKind: "Wi‑Fi").contains("读不到内核"))
    }
}
