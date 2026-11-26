import Foundation
import Testing
@testable import ParalluxKit

@Suite struct LinkSettingsTests {
    private let links = [
        LinkInterface(name: "en0", kind: .wifi, displayName: "Wi‑Fi"),
        LinkInterface(name: "en7", kind: .ethernet, displayName: "USB LAN"),
        LinkInterface(name: "en8", kind: .iPhone, displayName: "iPhone USB"),
    ]

    @Test func linkSettingsRoundTripWithDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "parallux-links-\(UUID().uuidString)"))
        let fresh = LinkSettings.load(from: defaults)
        #expect(fresh == LinkSettings())
        #expect(fresh.mode == AppSettings().defaultAggregationMode)
        var changed = fresh
        changed.mode = .failover
        changed.preferences.order = ["en8", "en0"]
        changed.preferences.disabled = ["en7"]
        changed.preferences.backup = ["en8"]
        changed.bondServerID = UUID()
        changed.save(to: defaults)
        #expect(LinkSettings.load(from: defaults) == changed)
        defaults.set(Data(#"{"mode":"balance"}"#.utf8), forKey: LinkSettings.defaultsKey)
        let partial = LinkSettings.load(from: defaults)
        #expect(partial.mode == .balance)
        #expect(partial.preferences == LinkPreferences())
    }

    @Test func flowColumnsFollowTheLinks() throws {
        let exits = [FlowSummary.Exit(name: "HK-03", rate: 300), FlowSummary.Exit(name: "直连", rate: 100)]
        let none = LinkFlow.columns(links: [], linkRates: [:], totalRate: 400, exits: exits)
        #expect(none.left.isEmpty)
        let one = LinkFlow.columns(links: [links[0]], linkRates: [:], totalRate: 400, exits: exits)
        #expect(one.left.map(\.rate) == [400], "one link carries the total")
        #expect(one.right.map(\.title) == ["HK-03", "直连"])
        let rates: [String: LinkRates.Rate] = [
            "link-en0": .init(upload: 10, download: 90), "link-en7": .init(upload: 0, download: 250), "link-en8": .init(upload: 0, download: 0),
        ]
        let three = LinkFlow.columns(links: links, linkRates: rates, totalRate: 350, exits: exits)
        try #require(three.left.map(\.id) == ["en0", "en7", "en8"])
        #expect(three.left.map(\.rate) == [100, 250, 0])
        #expect(three.left.map(\.title) == ["Wi‑Fi", "有线", "iPhone"])
        #expect(three.left[0].detail.contains("en0"))
    }

    @Test func sharedEgressIsReportedByName() throws {
        #expect(SharedEgress.warning(links: links, egress: [:]) == nil)
        #expect(SharedEgress.warning(links: links, egress: ["en0": "1.1.1.1", "en7": "2.2.2.2"]) == nil)
        let warning = try #require(SharedEgress.warning(links: links, egress: ["en0": "1.1.1.1", "en7": "1.1.1.1", "en8": "3.3.3.3"]))
        #expect(warning.contains("Wi‑Fi"))
        #expect(warning.contains("有线"))
        #expect(!warning.contains("iPhone"))
        #expect(SharedEgress.warning(links: [links[0]], egress: ["en0": "1.1.1.1"]) == nil)
    }
}

@Suite struct LinkRecompositionTests {
    private let wifi = LinkInterface(name: "en0", kind: .wifi, displayName: "Wi‑Fi", address: "10.0.0.2")
    private let lan = LinkInterface(name: "en7", kind: .ethernet, displayName: "LAN", address: "192.168.1.2")
    private let iPhone = LinkInterface(name: "en8", kind: .iPhone, displayName: "iPhone USB")

    @Test func linkSetChangesTriggerRecomposition() {
        var prefs = LinkPreferences()
        #expect(prefs.needsRecomposition(from: [wifi], to: [wifi, lan]), "plugged in")
        #expect(prefs.needsRecomposition(from: [wifi, lan], to: [wifi]), "pulled out")
        var moved = lan
        moved.address = "192.168.1.99"
        #expect(!prefs.needsRecomposition(from: [wifi, lan], to: [wifi, moved]), "address change only")
        #expect(!prefs.needsRecomposition(from: [wifi, lan], to: [lan, wifi]), "order of discovery only")
        #expect(!prefs.needsRecomposition(from: [], to: []))
        prefs.disabled = ["en8"]
        #expect(!prefs.needsRecomposition(from: [wifi, lan], to: [wifi, lan, iPhone]), "a disabled link appearing")
    }
}

@Suite struct FlowFallbackTests {
    private let links = [
        LinkInterface(name: "en0", kind: .wifi, displayName: "Wi‑Fi"),
        LinkInterface(name: "en7", kind: .ethernet, displayName: "LAN"),
    ]

    @Test func linkRatesFallBackToAnEvenSplitWithoutCounters() {
        let none = LinkFlow.columns(links: links, linkRates: [:], totalRate: 1000, exits: [])
        #expect(none.left.map(\.rate) == [500, 500])
        let one = LinkFlow.columns(links: links, linkRates: ["link-en0": .init(upload: 0, download: 300)], totalRate: 1000, exits: [])
        #expect(one.left.map(\.rate) == [300, 0], "measured counters win")
        #expect(LinkFlow.columns(links: links, linkRates: [:], totalRate: 0, exits: []).left.map(\.rate) == [0, 0])
    }

    @Test func zeroRateNodesAreSpacedEvenly() {
        let layout = SankeyLayout.make(left: [0, 0], right: [0, 0, 0], height: 240, gap: 8)
        #expect(layout.bands.isEmpty)
        #expect(layout.right.count == 3)
        let mids = layout.right.map { ($0.lower + $0.upper) / 2 }
        #expect(Set(mids).count == 3, "labels would stack at one y")
        #expect(mids == mids.sorted())
        #expect(layout.right.allSatisfy { $0.lower >= 0 && $0.upper <= 240 })
    }
}
