import Foundation
import Testing
@testable import ParalluxKit

/// fix-link-alerts-single-line: a link notification is worth showing only
/// when there is another line to fall back to, the change lasted, and the
/// text says where traffic actually goes.
@Suite struct LinkAlertsTests {
    private let names = ["link-en0": "Wi‑Fi（en0）", "link-en7": "有线（en7）"]
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    /// Feeds one sample per second; `health(second)` gives that second's states.
    private func run(seconds: Int, names: [String: String]? = nil,
                     _ health: (Int) -> [String: Bool]) -> [(second: Int, alert: LinkAlerts.Alert)] {
        var alerts = LinkAlerts()
        var out: [(Int, LinkAlerts.Alert)] = []
        for second in 0...seconds {
            let now = start.addingTimeInterval(TimeInterval(second))
            for alert in alerts.step(health: health(second), names: names ?? self.names, now: now) {
                out.append((second, alert))
            }
        }
        return out
    }

    @Test func aSingleLinkNeverAlertsHoweverLongItIsDown() {
        // Wi‑Fi alone: down from 5 s to 40 s, then back.
        let alerts = run(seconds: 60) { ["link-en0": !(5..<40).contains($0)] }
        #expect(alerts.isEmpty)
    }

    @Test func aFlapShorterThanTheHoldStaysQuiet() {
        // Two links; Wi‑Fi drops for 3 s, as in the author's 21:17 and 21:58 pairs.
        let alerts = run(seconds: 30) { ["link-en0": !(5..<8).contains($0), "link-en7": true] }
        #expect(alerts.isEmpty)
    }

    @Test func aLinkDownPastTheHoldNamesTheLinesTrafficMovesTo() throws {
        let alerts = run(seconds: 40) { ["link-en0": $0 < 5, "link-en7": true] }
        #expect(alerts.count == 1)
        let down = try #require(alerts.first)
        #expect(down.alert.tag == "link-en0")
        #expect(down.alert.healthy == false)
        #expect(down.second >= 5 + Int(LinkAlerts.hold), "announced only once the drop lasted the hold")
        #expect(down.alert.body.contains("Wi‑Fi（en0）"))
        #expect(down.alert.body.contains("有线（en7）"), "says which line takes the new connections")
        #expect(!down.alert.body.contains("其他线路"))
    }

    @Test func aRecoveryIsAnnouncedOnlyAfterItsDropWas() {
        // Wi‑Fi drops while 有线 is down too (nothing to fall back to: quiet),
        // then comes back: no 「已恢复」 for a drop nobody was told about.
        let quiet = run(seconds: 60) { ["link-en0": !(5..<30).contains($0), "link-en7": false] }
        #expect(quiet.isEmpty)

        // Announced drop, then recovery past the hold: exactly down, up.
        let pair = run(seconds: 60) { ["link-en0": !(5..<30).contains($0), "link-en7": true] }
        #expect(pair.map(\.alert.healthy) == [false, true])
        #expect(pair.last?.alert.title == "线路已恢复")
    }

    @Test func aLinkMissingFromTheListKeepsItsLastNameAndNeverShowsItsTag() throws {
        // The inventory names en0 only at first (it then drops out of the
        // list, as when Wi‑Fi changes network); a never-listed link shows its
        // interface, not the outbound tag.
        var alerts = LinkAlerts()
        var out: [LinkAlerts.Alert] = []
        for second in 0...40 {
            let listed = second == 0 ? ["link-en0": "Wi‑Fi（en0）"] : [:]
            let health = ["link-en0": second < 5, "link-en9": true]
            out += alerts.step(health: health, names: listed, now: start.addingTimeInterval(TimeInterval(second)))
        }
        let down = try #require(out.first)
        #expect(down.body.contains("Wi‑Fi（en0）"))
        #expect(!down.body.contains("link-"))
        #expect(down.body.contains("en9"))
    }

    /// INV-21 over random timelines: alerts per link alternate starting with
    /// a drop; a drop is announced only while another link is healthy; every
    /// announced state held for the whole hold; nothing for a lone link.
    @Test func randomTimelinesOnlyAnnounceLastingChangesWithAFallback() {
        var rng = SplitMix64(seed: 0xA1E7)
        let tags = ["link-en0", "link-en7", "link-en9"]
        var total = 0
        for _ in 0..<300 {
            let count = 1 + rng.int(3)
            let present = Array(tags.prefix(count))
            var timeline: [[String: Bool]] = []
            var state = Dictionary(uniqueKeysWithValues: present.map { ($0, true) })
            for _ in 0..<120 {
                for tag in present where rng.int(8) == 0 { state[tag]?.toggle() }
                timeline.append(state)
            }
            var alerts = LinkAlerts()
            var announced: [String: [Bool]] = [:]
            for (second, health) in timeline.enumerated() {
                let now = start.addingTimeInterval(TimeInterval(second))
                for alert in alerts.step(health: health, names: [:], now: now) {
                    #expect(count >= 2, "a lone link never alerts")
                    let held = Int(LinkAlerts.hold)
                    #expect(second >= held)
                    if second >= held {
                        for back in (second - held)...second {
                            #expect(timeline[back][alert.tag] == alert.healthy, "the announced state lasted the hold")
                        }
                    }
                    if !alert.healthy {
                        #expect(health.contains { $0.key != alert.tag && $0.value }, "a drop has a line to fall back to")
                    }
                    announced[alert.tag, default: []].append(alert.healthy)
                    total += 1
                }
            }
            for (_, sequence) in announced {
                for (index, healthy) in sequence.enumerated() {
                    #expect(healthy == !index.isMultiple(of: 2), "drop, recovery, drop, …")
                }
            }
        }
        #expect(total > 100, "the timelines do produce alerts, so the checks above are not vacuous")
    }
}
