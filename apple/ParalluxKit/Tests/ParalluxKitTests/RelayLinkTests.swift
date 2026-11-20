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

/// Sixteen obviously fake bytes ("0123456789abcdef"); never a real key.
private let key = "MDEyMzQ1Njc4OWFiY2RlZg=="
private let encodedKey = "MDEyMzQ1Njc4OWFiY2RlZg%3D%3D"
private let method = "2022-blake3-aes-128-gcm"

private func outbounds(_ json: String) throws -> [[String: Any]] {
    let root = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    return try #require(root["outbounds"] as? [[String: Any]])
}

private let userProfile = """
{
  "dns": {"servers": [{"type": "local", "tag": "local"}]},
  "inbounds": [{"type": "tun", "tag": "tun-in", "auto_route": true}],
  "outbounds": [
    {"type": "selector", "tag": "Proxy", "outbounds": ["DE-01", "direct"]},
    {"type": "vless", "tag": "DE-01", "server": "de.example.com", "server_port": 443, "uuid": "00000000-0000-0000-0000-000000000000"},
    {"type": "direct", "tag": "direct", "domain_resolver": "local"}
  ],
  "route": {"final": "Proxy"}
}
"""

private let wifi = LinkInterface(name: "en0", kind: .wifi, displayName: "Wi‑Fi")
private let wired = LinkInterface(name: "en7", kind: .ethernet, displayName: "USB LAN")

private func relay(_ n: Int, carrier: String? = "en7") -> RelayLink {
    RelayLink(id: UUID(uuidString: "\(n)\(n)\(n)\(n)\(n)\(n)\(n)\(n)-2222-3333-4444-555555555555")!,
              name: "worker-\(n)", host: "10.0.0.2\(n)", port: 39100, method: method, carrier: carrier)
}

@Suite struct RelayLinkURLTests {
    @Test func relayLinksParseByTheV1Spec() throws {
        let parsed = try RelayLinkURL.parse("parallux://relay?v=1&host=10.0.0.21&port=39100&method=\(method)&key=\(encodedKey)#worker%201%20%E6%9C%BA%E6%88%BF")
        #expect(parsed.relay.host == "10.0.0.21")
        #expect(parsed.relay.port == 39100)
        #expect(parsed.relay.method == method)
        #expect(parsed.relay.name == "worker 1 机房")
        #expect(parsed.relay.carrier == nil, "the carrier is found by the app, not carried in the link")
        #expect(parsed.key == key)
        let v6 = try RelayLinkURL.parse("  parallux://relay?key=\(encodedKey)&port=1&host=2001%3Adb8%3A%3A21&method=\(method)&v=1&future=x\n")
        #expect(v6.relay.host == "2001:db8::21")
        #expect(v6.relay.name == "2001:db8::21", "no fragment: the name is the host")
        #expect(try RelayLinkURL.parse("parallux://relay?v=1&host=h&port=65535&method=\(method)&key=\(encodedKey)").relay.port == 65535)
        // "+" is not a space: a key with "+" and "/" survives.
        let plus = try RelayLinkURL.parse("parallux://relay?v=1&host=h&port=1&method=\(method)&key=ab%2B%2Fcd%2B%2Fef%2B%2Fgh%2B%2FijklmQ%3D%3D")
        #expect(plus.key == "ab+/cd+/ef+/gh+/ijklmQ==")

        func fails(_ link: String, _ expected: RelayLinkURL.Failure) {
            #expect(throws: expected, "\(link)") { try RelayLinkURL.parse(link) }
        }
        fails("https://relay?v=1&host=h&port=1&method=\(method)&key=\(encodedKey)", .notAParalluxLink)
        fails("parallux://aggregation-server?v=1&host=h&port=1&psk=0123456789abcdef0123", .notARelayLink)
        fails("parallux://relay?v=2&host=h&port=1&method=\(method)&key=\(encodedKey)", .unsupportedVersion("2"))
        fails("parallux://relay?host=h&port=1&method=\(method)&key=\(encodedKey)", .unsupportedVersion(nil))
        fails("parallux://relay?v=1&port=1&method=\(method)&key=\(encodedKey)", .missing("host"))
        fails("parallux://relay?v=1&host=h&method=\(method)&key=\(encodedKey)", .missing("port"))
        fails("parallux://relay?v=1&host=h&port=1&method=\(method)", .missing("key"))
        fails("parallux://relay?v=1&host=h&port=1&key=\(encodedKey)", .unsupportedMethod(nil))
        fails("parallux://relay?v=1&host=h&port=1&method=aes-128-gcm&key=\(encodedKey)", .unsupportedMethod("aes-128-gcm"))
        fails("parallux://relay?v=1&host=h&port=0&method=\(method)&key=\(encodedKey)", .badPort("0"))
        fails("parallux://relay?v=1&host=h&port=65536&method=\(method)&key=\(encodedKey)", .badPort("65536"))
        fails("parallux://relay?v=1&host=h&host=i&port=1&method=\(method)&key=\(encodedKey)", .duplicate("host"))
        // What the relay's shadowsocks refuses: unpadded, URL-safe, wrong length.
        fails("parallux://relay?v=1&host=h&port=1&method=\(method)&key=MDEyMzQ1Njc4OWFiY2RlZg", .badKey)
        fails("parallux://relay?v=1&host=h&port=1&method=\(method)&key=-_EyMzQ1Njc4OWFiY2RlZg%3D%3D", .badKey)
        fails("parallux://relay?v=1&host=h&port=1&method=\(method)&key=c2hvcnQ%3D", .badKey)
    }

    @Test func severalRelayLinksPasteAtOnce() throws {
        let one = "parallux://relay?v=1&host=10.0.0.21&port=39100&method=\(method)&key=\(encodedKey)#worker-1"
        let two = "parallux://relay?v=1&host=10.0.0.22&port=39100&method=\(method)&key=\(encodedKey)#worker-2"
        #expect(try RelayLinkURL.parseAll("").isEmpty)
        #expect(try RelayLinkURL.parseAll(" \n\n").isEmpty)
        #expect(try RelayLinkURL.parseAll(one).map(\.relay.name) == ["worker-1"])
        #expect(try RelayLinkURL.parseAll("\n\(one)\r\n\n  \(two)  \n").map(\.relay.host) == ["10.0.0.21", "10.0.0.22"])
        #expect(throws: RelayLinkURL.LineFailure(line: 3, failure: .notAParalluxLink)) {
            try RelayLinkURL.parseAll("\(one)\n\nnot a link\n\(two)")
        }
    }
}

@MainActor @Suite struct RelayLinkStoreTests {
    private func makeDefaults() -> UserDefaults {
        let name = "parallux.tests.relay.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func aRelayStoreKeepsKeysOutOfDefaultsAndSurvivesAReload() throws {
        let defaults = makeDefaults()
        let secrets = MemorySecrets()
        let store = RelayLinkStore(defaults: defaults, secrets: secrets)
        #expect(store.relays.isEmpty)
        let added = try store.add(relay(1, carrier: nil), key: key)
        #expect(store.relays == [added])
        #expect(store.key(for: added.id) == key)
        let saved = String(decoding: try #require(defaults.data(forKey: RelayLinkStore.defaultsKey)), as: UTF8.self)
        #expect(!saved.contains(key), "the key must not be written to UserDefaults")
        #expect(saved.contains("10.0.0.21"))

        store.setCarrier("en7", for: added.id)
        store.rename(added.id, to: "机房 1")
        let reloaded = RelayLinkStore(defaults: defaults, secrets: secrets)
        #expect(reloaded.relays.map(\.carrier) == ["en7"])
        #expect(reloaded.relays.map(\.name) == ["机房 1"])
        #expect(reloaded.key(for: added.id) == key)

        // The same host and port again replaces the entry (a reinstalled
        // relay), keeping its identity and its place in the links order.
        var again = relay(1, carrier: nil)
        again.id = UUID()
        again.name = "worker-1b"
        let replaced = try reloaded.add(again, key: "ab+/cd+/ef+/gh+/ijklmQ==")
        #expect(reloaded.relays.count == 1)
        #expect(replaced.id == added.id)
        #expect(reloaded.relays.first?.name == "worker-1b")
        #expect(reloaded.key(for: added.id) == "ab+/cd+/ef+/gh+/ijklmQ==")
        #expect(secrets.count == 1)

        reloaded.remove(added.id)
        #expect(reloaded.relays.isEmpty)
        #expect(secrets.count == 0, "removing a relay removes its key")
        #expect(RelayLinkStore(defaults: defaults, secrets: secrets).relays.isEmpty)
    }

    @Test func aRelayStoreStopsAtItsLimit() throws {
        let store = RelayLinkStore(defaults: makeDefaults(), secrets: MemorySecrets())
        for n in 0..<RelayLinkStore.limit {
            try store.add(RelayLink(name: "w\(n)", host: "10.0.1.\(n)", port: 39100, method: method), key: key)
        }
        #expect(store.relays.count == RelayLinkStore.limit)
        #expect(throws: RelayLinkStore.Failure.full(RelayLinkStore.limit)) {
            try store.add(RelayLink(name: "one too many", host: "10.0.2.1", port: 39100, method: method), key: key)
        }
        #expect(store.relays.count == RelayLinkStore.limit)
        // Replacing an existing one is not growth.
        try store.add(RelayLink(name: "again", host: "10.0.1.0", port: 39100, method: method), key: key)
        #expect(store.relays.count == RelayLinkStore.limit)
        #expect(store.relays.first?.name == "again")
    }
}

@Suite struct RelayCompositionTests {
    @Test func aRelayIsALinkNamedAfterItsHost() throws {
        let one = relay(1)
        #expect(one.linkName == "relay-11111111")
        #expect(one.link == LinkInterface(name: "relay-11111111", kind: .relay, displayName: "worker-1", address: "10.0.0.21"))
        #expect(one.link.title == "worker-1", "a relay row is called by its name")
        #expect(wifi.title == "Wi‑Fi")
        #expect(wired.title == "有线")
        let composed = try #require(one.composed(key: key))
        #expect(composed.name == "relay-11111111")
        #expect(composed.carrier == "en7")
        #expect(composed.outbound == [
            "type": .string("shadowsocks"), "server": .string("10.0.0.21"), "server_port": .number(39100),
            "method": .string(method), "password": .string(key),
        ])
        #expect(relay(1, carrier: nil).composed(key: key) == nil, "no carrier, nothing to compose")
    }

    @Test func relaysJoinEveryAggregateAndDialThroughTheirCarrier() throws {
        let one = relay(1), two = relay(2)
        let relays = [try #require(one.composed(key: key)), try #require(two.composed(key: key))]
        // Priority order is the caller's: a relay may sit before a physical link.
        let links = [wifi, one.link, wired, two.link]
        let after = try outbounds(ProfileComposer.compose(userProfile, links: links, backup: [two.linkName], mode: .balance, relays: relays))
        let tags = ["link-en0", "link-relay-11111111", "link-en7", "link-relay-22222222"]
        for tag in ["direct", ProfileComposer.aggregateTag] {
            let aggregate = try #require(after.first { $0["tag"] as? String == tag })
            #expect(aggregate["type"] as? String == "aggregate", "\(tag)")
            #expect(aggregate["links"] as? [String] == tags, "\(tag)")
            #expect(aggregate["relays"] as? [String] == ["link-relay-11111111", "link-relay-22222222"], "\(tag)")
            #expect(aggregate["backup"] as? [String] == ["link-relay-22222222"], "\(tag)")
        }
        let outbound = try #require(after.first { $0["tag"] as? String == "link-relay-11111111" })
        #expect(outbound["type"] as? String == "shadowsocks")
        #expect(outbound["detour"] as? String == "link-en7", "a relay dials through its carrier, never through the aggregate")
        #expect(outbound["server"] as? String == "10.0.0.21")
        #expect(outbound["server_port"] as? Int == 39100)
        #expect(outbound["method"] as? String == method)
        #expect(outbound["password"] as? String == key)
        #expect(outbound["bind_interface"] == nil)
        #expect(outbound["domain_resolver"] == nil, "the user's direct dial options belong to the physical links")
        let node = try #require(after.first { $0["tag"] as? String == "DE-01" })
        #expect(node["detour"] as? String == ProfileComposer.aggregateTag)
        // Without relays nothing mentions them.
        let plain = try outbounds(ProfileComposer.compose(userProfile, links: [wifi, wired], backup: [], mode: .balance))
        #expect(plain.allSatisfy { $0["relays"] == nil })
    }

    @Test func aRelayWithoutItsCarrierIsLeftOut() throws {
        let one = relay(1), stray = relay(2, carrier: "en9")
        let relays = [try #require(one.composed(key: key)), try #require(stray.composed(key: key))]
        let after = try outbounds(ProfileComposer.compose(userProfile, links: [wifi, wired, one.link, stray.link], backup: [stray.linkName], mode: .failover, relays: relays))
        let aggregate = try #require(after.first { $0["tag"] as? String == ProfileComposer.aggregateTag })
        #expect(aggregate["links"] as? [String] == ["link-en0", "link-en7", "link-relay-11111111"])
        #expect(aggregate["relays"] as? [String] == ["link-relay-11111111"])
        #expect(aggregate["backup"] == nil, "a dropped relay is not a backup either")
        #expect(!after.contains { $0["tag"] as? String == "link-relay-22222222" })
        // A relay link nobody described (no key) is dropped too.
        let undescribed = try outbounds(ProfileComposer.compose(userProfile, links: [wifi, wired, one.link], backup: [], mode: .failover))
        #expect(!undescribed.contains { $0["tag"] as? String == "link-relay-11111111" })
        #expect(try #require(undescribed.first { $0["tag"] as? String == "direct" })["links"] as? [String] == ["link-en0", "link-en7"])
        // Its carrier switched off: en7 is not among the links.
        let off = try ProfileComposer.compose(userProfile, links: [wifi, one.link], backup: [], mode: .balance, relays: relays)
        #expect(off == userProfile, "one usable link is not aggregation")
    }

    @Test func onePhysicalLinkAndARelayAreEnoughToAggregate() throws {
        let one = relay(1)
        let relays = [try #require(one.composed(key: key))]
        let after = try outbounds(ProfileComposer.compose(userProfile, links: [wired, one.link], backup: [], mode: .balance, relays: relays))
        let aggregate = try #require(after.first { $0["tag"] as? String == ProfileComposer.aggregateTag })
        #expect(aggregate["links"] as? [String] == ["link-en7", "link-relay-11111111"])
        // 0 and 1 usable links leave the profile alone.
        #expect(try ProfileComposer.compose(userProfile, links: [one.link], backup: [], mode: .balance, relays: relays) == userProfile)
        #expect(try ProfileComposer.compose(userProfile, links: [wired], backup: [], mode: .balance, relays: relays) == userProfile)
        #expect(try ProfileComposer.compose(userProfile, links: [], backup: [], mode: .balance, relays: relays) == userProfile)
    }

    @Test func relaysAreNeverLegsOfTheBond() throws {
        let one = relay(1)
        let relays = [try #require(one.composed(key: key))]
        let fragment = ProfileComposer.Bond(tag: "parallux-bond", outbound: [
            "type": .string("multipath"), "server": .string("203.0.113.10"), "server_port": .number(39000), "psk": .string("change-me"),
        ])
        let after = try outbounds(ProfileComposer.compose(userProfile, links: [one.link, wifi, wired], backup: [], mode: .bond, bond: fragment, relays: relays))
        let multipath = try #require(after.first { $0["tag"] as? String == "parallux-bond" })
        #expect(multipath["outbounds"] as? [String] == ["link-en0", "link-en7"], "the transport has two legs, both physical")
        let aggregate = try #require(after.first { $0["tag"] as? String == ProfileComposer.aggregateTag })
        #expect(aggregate["mode"] as? String == "bond")
        #expect(aggregate["links"] as? [String] == ["link-relay-11111111", "link-en0", "link-en7"])
        // One physical link cannot bond, whatever the relays: 主备 over the links.
        let single = try outbounds(ProfileComposer.compose(userProfile, links: [wired, one.link], backup: [], mode: .bond, bond: fragment, relays: relays))
        #expect(!single.contains { $0["type"] as? String == "multipath" })
        #expect(try #require(single.first { $0["tag"] as? String == ProfileComposer.aggregateTag })["mode"] as? String == "failover")
        // The server's own fragment picks physical links only.
        let server = AggregationServer(name: "vps", host: "203.0.113.10", port: 39000)
        let legs = try #require(server.bond(links: [one.link, wifi, wired], psk: "change-me")).outbound["outbounds"]
        #expect(legs == .array([.string("link-en0"), .string("link-en7")]))
        #expect(server.bond(links: [wired, one.link], psk: "change-me") == nil, "one physical link is not a bond")
    }

    /// INV-5 with relays: every reference resolves, and following detours
    /// and aggregate links never comes back to where it started.
    @Test func composingWithRelaysKeepsEveryTagAndNeverLoops() throws {
        var rng = SplitMix64(seed: 0xD24)
        let physical = [wifi, wired, LinkInterface(name: "en8", kind: .iPhone, displayName: "iPhone USB")]
        let fragment = ProfileComposer.Bond(tag: "parallux-bond", outbound: [
            "type": .string("multipath"), "server": .string("203.0.113.10"), "server_port": .number(39000), "psk": .string("change-me"),
        ])
        var composedWithRelays = 0
        for _ in 0..<400 {
            let carriers: [String?] = ["en0", "en7", "en8", "en9", nil]
            let pool = (1...3).map { relay($0, carrier: carriers[rng.int(carriers.count)]) }
            var links = physical.filter { _ in rng.bool() } + pool.filter { _ in rng.bool() }.map(\.link)
            for index in links.indices.reversed() where index > 0 { links.swapAt(index, rng.int(index + 1)) }
            let relays = pool.filter { _ in rng.int(4) > 0 }.compactMap { $0.composed(key: key) }
            let backup = Set(links.map(\.name).filter { _ in rng.int(3) == 0 })
            let mode = AggregationMode.allCases[rng.int(AggregationMode.allCases.count)]
            let composed = try ProfileComposer.compose(userProfile, links: links, backup: backup, mode: mode,
                                                       bond: rng.bool() ? fragment : nil, relays: relays)
            let after = try outbounds(composed)
            // uniquingKeysWith: duplicate tags must fail the expectation below, not crash the run.
            let byTag = Dictionary(after.compactMap { outbound in (outbound["tag"] as? String).map { ($0, outbound) } }, uniquingKeysWith: { first, _ in first })
            #expect(byTag.count == after.count, "duplicate or missing tags")
            for tag in try outbounds(userProfile).compactMap({ $0["tag"] as? String }) { #expect(byTag[tag] != nil, "the user's \(tag) disappeared") }

            func references(_ outbound: [String: Any]) -> [String] {
                var result = (outbound["outbounds"] as? [String]) ?? []
                result += (outbound["links"] as? [String]) ?? []
                for key in ["detour", "bond"] { if let tag = outbound[key] as? String { result.append(tag) } }
                return result
            }
            for outbound in after {
                for tag in references(outbound) + ((outbound["backup"] as? [String]) ?? []) + ((outbound["relays"] as? [String]) ?? []) {
                    #expect(byTag[tag] != nil, "\(outbound["tag"] ?? "?") refers to \(tag), which does not exist")
                }
                if outbound["type"] as? String == "aggregate" {
                    let members = Set((outbound["links"] as? [String]) ?? [])
                    #expect(Set((outbound["relays"] as? [String]) ?? []).isSubset(of: members))
                    #expect(Set((outbound["backup"] as? [String]) ?? []).isSubset(of: members))
                    #expect(members.count >= 2, "an aggregate of fewer than two links")
                }
                if outbound["type"] as? String == "multipath" {
                    let legs = (outbound["outbounds"] as? [String]) ?? []
                    #expect(legs.count == 2)
                    #expect(legs.allSatisfy { byTag[$0]?["type"] as? String == "direct" }, "a bond leg is not a physical link: \(legs)")
                }
            }
            for relayLink in pool {
                guard let outbound = byTag[ProfileComposer.linkTag(relayLink.linkName)] else { continue }
                composedWithRelays += 1
                let detour = try #require(outbound["detour"] as? String)
                let carrier = try #require(byTag[detour])
                #expect(carrier["type"] as? String == "direct")
                #expect(carrier["bind_interface"] as? String == relayLink.carrier)
            }
            // No cycle: depth-first over the reference graph.
            var state: [String: Int] = [:] // 1 = on the stack, 2 = done
            func visit(_ tag: String) -> Bool {
                if state[tag] == 1 { return false }
                if state[tag] == 2 { return true }
                state[tag] = 1
                for next in references(byTag[tag] ?? [:]) where !visit(next) { return false }
                state[tag] = 2
                return true
            }
            for tag in byTag.keys { #expect(visit(tag), "the outbounds refer to each other in a loop through \(tag)") }
        }
        #expect(composedWithRelays > 50, "the generator rarely produced a usable relay (\(composedWithRelays)); the property proves little")
    }
}

@Suite struct RelayRateTests {
    @Test func relayRatesComeFromTheCoreAndLeaveTheCarrier() {
        func rate(_ up: Int64, _ down: Int64) -> LinkRates.Rate { .init(upload: up, download: down) }
        let interface = ["link-en0": rate(10, 100), "link-en7": rate(50, 900)]
        let counted = ["link-en0": rate(1, 1), "link-en7": rate(2, 2), "link-relay-a": rate(10, 300), "link-relay-b": rate(5, 200), "link-relay-c": rate(7, 7)]
        let carriers = ["link-relay-a": "link-en7", "link-relay-b": "link-en7", "link-relay-z": "link-en0"]
        let merged = RelayRates.merge(interface: interface, counted: counted, carriers: carriers)
        #expect(merged["link-relay-a"] == rate(10, 300))
        #expect(merged["link-relay-b"] == rate(5, 200))
        #expect(merged["link-relay-z"] == rate(0, 0), "a relay the core has not counted yet reads 0")
        #expect(merged["link-relay-c"] == nil, "not a relay the app knows: its counter is not shown")
        #expect(merged["link-en7"] == rate(35, 400), "the carrier shows what it carries for itself")
        #expect(merged["link-en0"] == rate(10, 100), "physical links keep their interface rate, not the core's")
        // The relay's bytes are counted before encryption and at another
        // instant: the carrier never goes negative.
        let over = RelayRates.merge(interface: ["link-en7": rate(5, 100)], counted: ["link-relay-a": rate(10, 300)], carriers: ["link-relay-a": "link-en7"])
        #expect(over["link-en7"] == rate(0, 0))
        // A carrier the interface counters do not list is not invented.
        let absent = RelayRates.merge(interface: [:], counted: ["link-relay-a": rate(1, 2)], carriers: ["link-relay-a": "link-en7"])
        #expect(absent == ["link-relay-a": rate(1, 2)])
        #expect(RelayRates.merge(interface: interface, counted: counted, carriers: [:]) == interface)
        #expect(RelayRates.merge(interface: [:], counted: [:], carriers: [:]).isEmpty)
    }
}
