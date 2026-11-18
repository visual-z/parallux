import AppKit
import Foundation
import Testing
@testable import ParalluxKit

@Suite struct SankeyLayoutTests {
    @Test func aSankeyLayoutConservesWidth() {
        var rng = SplitMix64(seed: 0x5A4E)
        let rateChoices: [Double] = [0, 1, 95, 420, 1e9]
        for round in 0..<300 {
            let leftCount = round == 0 ? 0 : rng.int(5)
            let rightCount = round == 0 ? 0 : rng.int(6)
            let left = (0..<leftCount).map { _ in rateChoices[rng.int(rateChoices.count)] }
            let right = (0..<rightCount).map { _ in rateChoices[rng.int(rateChoices.count)] }
            let layout = SankeyLayout.make(left: left, right: right, height: 240, gap: 8)
            let total = left.reduce(0, +)
            #expect(layout.left.count == left.count)
            #expect(layout.right.count == right.count)
            if total == 0 || right.reduce(0, +) == 0 {
                #expect(layout.bands.isEmpty, "no traffic, no bands")
                continue
            }
            let leftSum = layout.left.map(\.length).reduce(0, +)
            let rightSum = layout.right.map(\.length).reduce(0, +)
            #expect(abs(leftSum - rightSum) < 1e-6)
            #expect(abs(layout.total.length - leftSum) < 1e-6)
            #expect(layout.total.length <= 240 + 1e-6)
            for (index, node) in layout.left.enumerated() {
                let bands = layout.bands.filter { $0.from == index }
                #expect(abs(bands.map(\.left.length).reduce(0, +) - node.length) < 1e-6)
                for band in bands { #expect(band.left.lower >= node.lower - 1e-6 && band.left.upper <= node.upper + 1e-6) }
            }
            for (index, node) in layout.right.enumerated() {
                let bands = layout.bands.filter { $0.to == index }
                #expect(abs(bands.map(\.right.length).reduce(0, +) - node.length) < 1e-6)
                for band in bands { #expect(band.right.lower >= node.lower - 1e-6 && band.right.upper <= node.upper + 1e-6) }
            }
        }
    }
}

@Suite struct AppSettingsTests {
    @Test func settingsRoundTripThroughUserDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "parallux-test-\(UUID().uuidString)"))
        let fresh = AppSettings.load(from: defaults)
        #expect(fresh == AppSettings())
        #expect(fresh.keepInMenuBarAfterClose)
        #expect(!fresh.showRateInMenuBar)
        #expect(fresh.defaultAggregationMode == .bond)
        var changed = fresh
        changed.showRateInMenuBar = true
        changed.tunnel.includeAllNetworks = true
        changed.onDemandEnabled = true
        changed.onDemandRules = [OnDemandRuleModel(match: .wifi(ssid: "Corp-5G"), action: .connect)]
        changed.save(to: defaults)
        #expect(AppSettings.load(from: defaults) == changed)
    }

    @Test func everyTunnelSettingReachesTheStartOptions() {
        let keyPaths: [(WritableKeyPath<TunnelSettings, Bool>, KeyPath<TunnelStartOptions, Bool>)] = [
            (\.includeAllNetworks, \.includeAllNetworks),
            (\.excludeLocalNetworks, \.excludeLocalNetworks),
            (\.excludeAPNs, \.excludeAPNs),
            (\.excludeDeviceCommunication, \.excludeDeviceCommunication),
            (\.enforceRoutes, \.enforceRoutes),
            (\.systemProxyEnabled, \.systemProxyEnabled),
            (\.excludeDefaultRoute, \.excludeDefaultRoute),
            (\.autoRouteUseSubRangesByDefault, \.autoRouteUseSubRangesByDefault),
        ]
        let base = AppSettings()
        let baseOptions = base.startOptions(content: "{}")
        #expect(baseOptions.configContent == "{}")
        for (index, (setting, option)) in keyPaths.enumerated() {
            var settings = base
            settings.tunnel[keyPath: setting].toggle()
            let options = settings.startOptions(content: "{}")
            #expect(options[keyPath: option] == settings.tunnel[keyPath: setting], "field \(index)")
            for (other, (_, otherOption)) in keyPaths.enumerated() where other != index {
                #expect(options[keyPath: otherOption] == baseOptions[keyPath: otherOption], "field \(other) moved with \(index)")
            }
        }
    }

    @Test func onDemandRulesValidateAndRoundTrip() throws {
        #expect(OnDemandRuleModel(match: .wifi(ssid: ""), action: .connect).problem != nil)
        #expect(OnDemandRuleModel(match: .wifi(ssid: "Corp-5G"), action: .connect).problem == nil)
        #expect(OnDemandRuleModel(match: .probe(url: "ftp://x"), action: .disconnect).problem != nil)
        #expect(OnDemandRuleModel(match: .probe(url: "not a url"), action: .disconnect).problem != nil)
        #expect(OnDemandRuleModel(match: .probe(url: "http://intranet.local"), action: .disconnect).problem == nil)
        #expect(OnDemandRuleModel(match: .anyNetwork, action: .connect).problem == nil)
        let rules = [
            OnDemandRuleModel(match: .wifi(ssid: "Corp-5G"), action: .connect),
            OnDemandRuleModel(match: .probe(url: "http://intranet.local"), action: .disconnect),
            OnDemandRuleModel(match: .anyNetwork, action: .connect),
        ]
        let decoded = try JSONDecoder().decode([OnDemandRuleModel].self, from: JSONEncoder().encode(rules))
        #expect(decoded == rules)
    }
}

@MainActor @Suite struct MenuBarIconTests {
    private func pixels(_ image: NSImage) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: [.ctm: AffineTransform(scale: 2)]) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .png, properties: [:])
    }

    @Test func menuBarIconsAreDistinctTemplates() throws {
        var seen: [Data] = []
        for state in MenuBarIcon.State.allCases {
            let image = MenuBarIcon.image(for: state)
            #expect(image.size == NSSize(width: 18, height: 18), "\(state)")
            #expect(image.isTemplate, "\(state)")
            let data = try #require(pixels(image))
            #expect(!seen.contains(data), "\(state) looks like another state")
            seen.append(data)
        }
    }
}

@Suite struct FlowSummaryTests {
    private func row(_ id: String, outbound: String, type: String, up: Int64, down: Int64) -> ConnectionRow {
        var row = ConnectionRow(id: id, process: "", destination: "", rule: "", outbound: outbound)
        row.outboundType = type
        row.uplink = up
        row.downlink = down
        return row
    }

    @Test func flowSummaryGroupsTrafficByExit() throws {
        #expect(FlowSummary.exits([]).isEmpty)
        #expect(FlowSummary.exits([row("0", outbound: "direct", type: "direct", up: 0, down: 0)]).isEmpty)
        let rows = [
            row("1", outbound: "direct", type: "direct", up: 10, down: 90),
            row("2", outbound: "direct-cn", type: "direct", up: 0, down: 50),
            row("3", outbound: "HK-03", type: "vmess", up: 20, down: 400),
            row("4", outbound: "JP-01", type: "trojan", up: 0, down: 30),
            row("5", outbound: "SG-02", type: "trojan", up: 0, down: 20),
            row("6", outbound: "US-05", type: "trojan", up: 0, down: 10),
            row("7", outbound: "US-09", type: "trojan", up: 0, down: 5),
        ]
        let exits = FlowSummary.exits(rows)
        try #require(exits.count == FlowSummary.maxExits + 1)
        #expect(exits.first == .init(name: "HK-03", rate: 420))
        #expect(exits[1] == .init(name: FlowSummary.directName, rate: 150))
        #expect(exits.last == .init(name: FlowSummary.otherName, rate: 15))
        #expect(exits.map(\.rate).reduce(0, +) == 635)
        #expect(FlowSummary.exits(Array(rows.prefix(3))).count == 2)
    }
}
