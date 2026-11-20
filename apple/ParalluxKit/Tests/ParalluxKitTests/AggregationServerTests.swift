import Foundation
import Testing
@testable import ParalluxKit

private final class MemorySecrets: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: String] = [:]
    func secret(for id: UUID) -> String? { lock.withLock { values[id] } }
    func setSecret(_ secret: String, for id: UUID) throws { lock.withLock { values[id] = secret } }
    func removeSecret(for id: UUID) { lock.withLock { values[id] = nil } }
    var count: Int { lock.withLock { values.count } }
}

private let psk = "Zq3x0b9Ck2mVv7yQ1nH8sJt4wE6rU5aPxLdFgTiO0Bc"

@Suite struct AggregationServerLinkTests {
    @Test func aggregationServerLinksParseByTheV1Spec() throws {
        let v4 = try AggregationServerLink.parse("parallux://aggregation-server?v=1&host=203.0.113.24&port=39000&psk=\(psk)#%E4%B8%9C%E4%BA%AC%20VPS")
        #expect(v4.server.host == "203.0.113.24")
        #expect(v4.server.port == 39000)
        #expect(v4.server.name == "东京 VPS")
        #expect(v4.psk == psk)
        let v6 = try AggregationServerLink.parse("parallux://aggregation-server?port=39000&psk=\(psk)&host=2001%3Adb8%3A%3A24&v=1&future=x")
        #expect(v6.server.host == "2001:db8::24")
        #expect(v6.server.name == "2001:db8::24", "no fragment: the name is the host")
        let plus = try AggregationServerLink.parse("parallux://aggregation-server?v=1&host=h.example.com&port=1&psk=a%2Bb%2Bcdefghijklmnop")
        #expect(plus.psk == "a+b+cdefghijklmnop", "%2B decodes to +; + is not a space")
        #expect(try AggregationServerLink.parse("parallux://aggregation-server?v=1&host=h&port=65535&psk=\(psk)").server.port == 65535)

        func fails(_ link: String, _ expected: AggregationServerLink.Failure) {
            #expect(throws: expected, "\(link)") { try AggregationServerLink.parse(link) }
        }
        fails("https://aggregation-server?v=1&host=h&port=1&psk=\(psk)", .notAParalluxLink)
        fails("parallux://import-remote-profile?v=1&host=h&port=1&psk=\(psk)", .notAnAggregationServerLink)
        fails("parallux://aggregation-server?v=2&host=h&port=1&psk=\(psk)", .unsupportedVersion("2"))
        fails("parallux://aggregation-server?host=h&port=1&psk=\(psk)", .unsupportedVersion(nil))
        fails("parallux://aggregation-server?v=1&port=1&psk=\(psk)", .missing("host"))
        fails("parallux://aggregation-server?v=1&host=h&psk=\(psk)", .missing("port"))
        fails("parallux://aggregation-server?v=1&host=h&port=1", .missing("psk"))
        fails("parallux://aggregation-server?v=1&host=h&port=0&psk=\(psk)", .badPort("0"))
        fails("parallux://aggregation-server?v=1&host=h&port=65536&psk=\(psk)", .badPort("65536"))
        fails("parallux://aggregation-server?v=1&host=h&port=x&psk=\(psk)", .badPort("x"))
        fails("parallux://aggregation-server?v=1&host=h&port=1&psk=short", .pskTooShort)
        fails("parallux://aggregation-server?v=1&host=h&host=i&port=1&psk=\(psk)", .duplicate("host"))
        fails("not a url at all", .notAParalluxLink)
    }
}

@MainActor @Suite struct AggregationServerStoreTests {
    @Test func serverListsNeverCarryThePSK() throws {
        let defaults = try #require(UserDefaults(suiteName: "parallux-servers-\(UUID().uuidString)"))
        let secrets = MemorySecrets()
        let store = AggregationServerStore(defaults: defaults, secrets: secrets)
        let server = AggregationServer(name: "东京 VPS", host: "203.0.113.24", port: 39000)
        try store.add(server, psk: psk)
        #expect(store.servers == [server])
        #expect(store.psk(for: server.id) == psk)
        let stored = try #require(defaults.data(forKey: AggregationServerStore.defaultsKey))
        #expect(!String(decoding: stored, as: UTF8.self).contains(psk))
        let reopened = AggregationServerStore(defaults: defaults, secrets: secrets)
        #expect(reopened.servers == [server])
        reopened.remove(server.id)
        #expect(reopened.servers.isEmpty)
        #expect(secrets.count == 0, "removing a server removes its psk")
        #expect(AggregationServerStore(defaults: defaults, secrets: secrets).servers.isEmpty)
    }
}

@Suite struct BondOutboundTests {
    @Test func theBondOutboundUsesTheTwoTopLinks() throws {
        let server = AggregationServer(name: "s", host: "203.0.113.24", port: 39000)
        let links = [
            LinkInterface(name: "en7", kind: .ethernet, displayName: "LAN"),
            LinkInterface(name: "en0", kind: .wifi, displayName: "Wi‑Fi"),
            LinkInterface(name: "en8", kind: .iPhone, displayName: "iPhone USB"),
        ]
        let bond = try #require(server.bond(links: links, psk: psk))
        #expect(bond.tag == AggregationServer.bondTag)
        #expect(bond.outbound["type"] == .string("multipath"))
        #expect(bond.outbound["server"] == .string("203.0.113.24"))
        #expect(bond.outbound["server_port"] == .number(39000))
        #expect(bond.outbound["psk"] == .string(psk))
        let composed = try ProfileComposer.compose(#"{"outbounds":[{"type":"direct","tag":"direct"}]}"#, links: links, backup: [], mode: .bond, bond: bond)
        let root = try #require(try JSONSerialization.jsonObject(with: Data(composed.utf8)) as? [String: Any])
        let mp = try #require((root["outbounds"] as? [[String: Any]])?.first { $0["type"] as? String == "multipath" })
        #expect(mp["outbounds"] as? [String] == ["link-en7", "link-en0"], "two legs: the transport has exactly two")
        #expect(server.bond(links: Array(links.prefix(1)), psk: psk) == nil)
        #expect(server.bond(links: [], psk: psk) == nil)
    }
}

@Suite struct SpeedTestTests {
    @Test func speedTestSummaryComparesBondToTheFastestLink() throws {
        let results = [
            SpeedTest.Result(label: "Wi‑Fi", rate: 1_000_000, isBond: false),
            SpeedTest.Result(label: "有线", rate: 2_000_000, isBond: false),
            SpeedTest.Result(label: "叠加", rate: 3_400_000, isBond: true),
        ]
        let met = try #require(SpeedTest.summary(results))
        #expect(met.contains("1.7"))
        #expect(met.contains("达标"))
        var below = results
        below[2].rate = 2_400_000
        let missed = try #require(SpeedTest.summary(below))
        #expect(missed.contains("1.2"))
        #expect(missed.contains("未达标"))
        #expect(SpeedTest.summary([results[2]]) == nil, "no single link to compare with")
        #expect(SpeedTest.summary([results[0], results[1]]) == nil, "no bond result")
        #expect(SpeedTest.summary([results[0], SpeedTest.Result(label: "叠加", rate: nil, isBond: true)]) == nil, "bond failed")
        #expect(SpeedTest.summary([]) == nil)
    }
}
