import Foundation
import Testing
@testable import ParalluxKit

private func outbounds(_ json: String) throws -> [[String: Any]] {
    let root = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    return try #require(root["outbounds"] as? [[String: Any]])
}

private let userProfile = """
{
  "inbounds": [{"type": "tun", "tag": "tun-in", "auto_route": true}],
  "outbounds": [
    {"type": "selector", "tag": "Proxy", "outbounds": ["HK-03", "JP-01", "direct"]},
    {"type": "vmess", "tag": "HK-03", "server": "hk.example.com", "server_port": 443, "uuid": "00000000-0000-0000-0000-000000000000"},
    {"type": "trojan", "tag": "JP-01", "server": "jp.example.com", "server_port": 443, "password": "x", "detour": "relay"},
    {"type": "shadowsocks", "tag": "relay", "server": "relay.example.com", "server_port": 8388, "method": "aes-128-gcm", "password": "x"},
    {"type": "direct", "tag": "direct", "domain_resolver": "local"},
    {"type": "block", "tag": "block"}
  ],
  "route": {"final": "Proxy"}
}
"""

private let twoLinks = [
    LinkInterface(name: "en0", kind: .wifi, displayName: "Wi‑Fi"),
    LinkInterface(name: "en7", kind: .ethernet, displayName: "USB LAN"),
]

@Suite struct LinkCompositionTests {
    @Test func composingKeepsEveryTagAndNoDanglingDetour() throws {
        var rng = SplitMix64(seed: 0xA66)
        let pool = twoLinks + [LinkInterface(name: "en8", kind: .iPhone, displayName: "iPhone USB")]
        for _ in 0..<300 {
            let links = pool.filter { _ in rng.bool() }
            let backup = Set(links.map(\.name).filter { _ in rng.int(3) == 0 })
            let mode = AggregationMode.allCases[rng.int(2) == 0 ? 0 : 2] // bond needs a server, tested below
            let composed = try ProfileComposer.compose(userProfile, links: links, backup: backup, mode: mode)
            let before = try outbounds(userProfile).compactMap { $0["tag"] as? String }
            let after = try outbounds(composed)
            let tags = Set(after.compactMap { $0["tag"] as? String })
            #expect(Set(before).isSubset(of: tags), "a user tag disappeared")
            #expect(tags.count == after.count, "duplicate tags")
            for outbound in after {
                if let detour = outbound["detour"] as? String { #expect(tags.contains(detour), "dangling detour \(detour)") }
                for member in (outbound["outbounds"] as? [String]) ?? [] { #expect(tags.contains(member), "dangling member \(member)") }
                for link in (outbound["links"] as? [String]) ?? [] { #expect(tags.contains(link), "dangling link \(link)") }
            }
            if links.count < 2 {
                #expect(composed == userProfile, "fewer than two links leaves the profile alone")
                continue
            }
            let direct = try #require(after.first { $0["tag"] as? String == "direct" })
            #expect(direct["type"] as? String == "aggregate")
            #expect(direct["mode"] as? String == mode.rawValue)
            #expect(direct["links"] as? [String] == links.map { ProfileComposer.linkTag($0.name) })
            #expect(Set((direct["backup"] as? [String]) ?? []) == Set(backup.map(ProfileComposer.linkTag)))
            for link in links {
                let outbound = try #require(after.first { $0["tag"] as? String == ProfileComposer.linkTag(link.name) })
                #expect(outbound["type"] as? String == "direct")
                #expect(outbound["bind_interface"] as? String == link.name)
                #expect(outbound["domain_resolver"] as? String == "local", "keeps the user's direct dial options")
            }
            let hk = try #require(after.first { $0["tag"] as? String == "HK-03" })
            #expect(hk["detour"] as? String == ProfileComposer.aggregateTag)
            let jp = try #require(after.first { $0["tag"] as? String == "JP-01" })
            #expect(jp["detour"] as? String == "relay", "an existing detour is kept")
        }
    }

    @Test func bondModeAddsTheMultipathOutboundOverTheLinks() throws {
        let bond = ProfileComposer.Bond(tag: "parallux-bond", outbound: [
            "type": .string("multipath"), "server": .string("203.0.113.10"), "server_port": .number(39000), "psk": .string("k"),
        ])
        let composed = try ProfileComposer.compose(userProfile, links: twoLinks, backup: [], mode: .bond, bond: bond)
        let after = try outbounds(composed)
        let mp = try #require(after.first { $0["tag"] as? String == "parallux-bond" })
        #expect(mp["type"] as? String == "multipath")
        #expect(mp["outbounds"] as? [String] == ["link-en0", "link-en7"])
        let aggregate = try #require(after.first { $0["tag"] as? String == ProfileComposer.aggregateTag })
        #expect(aggregate["mode"] as? String == "bond")
        #expect(aggregate["bond"] as? String == "parallux-bond")
        // Without a server, bond degrades to failover rather than failing to start.
        let degraded = try outbounds(ProfileComposer.compose(userProfile, links: twoLinks, backup: [], mode: .bond))
        #expect(degraded.first { $0["tag"] as? String == ProfileComposer.aggregateTag }?["mode"] as? String == "failover")
    }

    @Test func aProfileThatIsNotJSONIsRejected() {
        #expect(throws: ProfileComposer.Failure.notJSON) {
            try ProfileComposer.compose("not json", links: twoLinks, backup: [], mode: .balance)
        }
    }

    @Test func linkPreferencesOrderAndFilter() {
        var prefs = LinkPreferences()
        let all = twoLinks + [LinkInterface(name: "en8", kind: .iPhone, displayName: "iPhone USB")]
        #expect(prefs.enabled(all).map(\.name) == ["en0", "en7", "en8"])
        prefs.order = ["en8", "en0"]
        #expect(prefs.enabled(all).map(\.name) == ["en8", "en0", "en7"])
        prefs.disabled = ["en0"]
        #expect(prefs.enabled(all).map(\.name) == ["en8", "en7"])
        #expect(prefs.enabled([]).isEmpty)
    }
}

@Suite struct LinkInventoryTests {
    @Test func linkInventoryClassifiesInterfaces() throws {
        let up = UInt32(IFF_UP | IFF_RUNNING)
        let raws: [LinkInventory.Raw] = [
            .init(name: "en7", scType: "Ethernet", scDisplayName: "USB 10/100/1000 LAN", flags: up, ipv4: "192.168.8.23"),
            .init(name: "en0", scType: "IEEE80211", scDisplayName: "Wi-Fi", flags: up, ipv4: "10.20.4.117"),
            .init(name: "en8", scType: "Ethernet", scDisplayName: "iPhone USB", flags: up, ipv4: "172.20.10.4"),
            .init(name: "en9", scType: nil, scDisplayName: nil, flags: up, ipv4: "192.168.2.2"),
            .init(name: "en3", scType: "Ethernet", scDisplayName: "Thunderbolt Ethernet", flags: up, ipv4: nil),
            .init(name: "utun4", scType: nil, scDisplayName: nil, flags: up, ipv4: "172.19.0.1"),
            .init(name: "bridge0", scType: "Bridge", scDisplayName: "Thunderbolt Bridge", flags: up, ipv4: "169.254.1.1"),
            .init(name: "en5", scType: "Ethernet", scDisplayName: "Dock", flags: UInt32(IFF_UP), ipv4: "10.0.0.2"),
        ]
        let links = LinkInventory.classify(raws)
        try #require(links.map(\.name) == ["en0", "en7", "en8", "en9"])
        #expect(links.map(\.kind) == [.wifi, .ethernet, .iPhone, .other])
        #expect(links.map(\.displayName) == ["Wi-Fi", "USB 10/100/1000 LAN", "iPhone USB", "en9"])
        #expect(links[1].address == "192.168.8.23")
        #expect(LinkInventory.classify([]).isEmpty)
    }
}
