import Foundation
@testable import ParalluxKit
import Testing

@Suite struct ConnectionSwitchesTests {
    static let all: [ConnectionSwitches] = [.both, .none, .init(aggregation: true, proxy: false), .init(aggregation: false, proxy: true)]

    @Test func switchTogglesAreDecidedByWhatIsShown() {
        for stored in Self.all {
            #expect(ConnectionSwitches.shown(stored, running: false) == .none)
            #expect(ConnectionSwitches.shown(stored, running: true) == stored)
            for running in [false, true] {
                let shown = ConnectionSwitches.shown(stored, running: running)
                for which in ConnectionSwitches.Which.allCases {
                    for on in [false, true] {
                        let (next, action) = ConnectionSwitches.toggle(stored, running: running, which, on: on)
                        var expected = shown
                        switch which {
                        case .aggregation: expected.aggregation = on
                        case .proxy: expected.proxy = on
                        }
                        if expected == shown {
                            #expect(action == .nothing, "\(stored) \(running) \(which) \(on)")
                            continue
                        }
                        #expect(next == expected, "only what is shown plus this flip")
                        if expected == .none {
                            #expect(action == .disconnect)
                        } else if !running {
                            #expect(action == .connect)
                        } else {
                            #expect(action == .reload)
                        }
                    }
                }
            }
            let start = ConnectionSwitches.forStart(stored)
            #expect(start == (stored == .none ? .both : stored))
        }
        // From off, turning on proxy alone does not bring back aggregation.
        let (next, action) = ConnectionSwitches.toggle(.both, running: false, .proxy, on: true)
        #expect(next == ConnectionSwitches(aggregation: false, proxy: true))
        #expect(action == .connect)
    }

    @Test func aggregationOnlyRoutesEverythingDirectThroughTheLinks() throws {
        let user = """
        {"dns":{"servers":[{"type":"https","tag":"remote","server":"1.1.1.1","detour":"proxy"}]},
         "inbounds":[{"type":"tun","tag":"tun-in","address":["172.18.0.1/30"],"mtu":9000,"auto_route":true,"stack":"mixed"},
                     {"type":"mixed","tag":"mixed-in","listen_port":7890}],
         "outbounds":[{"type":"selector","tag":"proxy","outbounds":["a"]},{"type":"vless","tag":"a","server":"x","server_port":1},
                      {"type":"direct","tag":"direct"}],
         "route":{"rules":[{"rule_set":"cn","outbound":"direct"}],"final":"proxy","rule_set":[{"tag":"cn","type":"remote","url":"https://x"}]}}
        """
        for source in [user, nil, "not json"] {
            let made = DirectProfile.make(from: source)
            let root = try #require(try JSONSerialization.jsonObject(with: Data(made.utf8)) as? [String: Any])
            let outbounds = try #require(root["outbounds"] as? [[String: Any]])
            #expect(outbounds.count == 1)
            #expect(outbounds.first?["type"] as? String == "direct")
            let tag = try #require(outbounds.first?["tag"] as? String)
            let route = try #require(root["route"] as? [String: Any])
            #expect(route["final"] as? String == tag)
            #expect(route["rule_set"] == nil)
            let actions = (route["rules"] as? [[String: Any]] ?? []).map { $0["action"] as? String }
            #expect(actions == ["sniff", "hijack-dns"])
            let servers = try #require((root["dns"] as? [String: Any])?["servers"] as? [[String: Any]])
            #expect(servers.allSatisfy { $0["type"] as? String == "local" && $0["detour"] == nil })
            let inbounds = try #require(root["inbounds"] as? [[String: Any]])
            #expect(inbounds.count == 1)
            let tun = try #require(inbounds.first)
            #expect(tun["type"] as? String == "tun")
            if source == user {
                #expect(tun["mtu"] as? Int == 9000)
                #expect(tun["stack"] as? String == "mixed")
            }
            let links = [LinkInterface(name: "en0", kind: .wifi, displayName: "Wi-Fi"), LinkInterface(name: "en7", kind: .ethernet, displayName: "USB")]
            let composed = try ProfileComposer.compose(made, links: links, backup: [], mode: .balance)
            let croot = try #require(try JSONSerialization.jsonObject(with: Data(composed.utf8)) as? [String: Any])
            let couts = try #require(croot["outbounds"] as? [[String: Any]])
            let final = try #require((croot["route"] as? [String: Any])?["final"] as? String)
            #expect(couts.first { $0["tag"] as? String == final }?["type"] as? String == "aggregate")
        }
    }

    @Test func bondWithoutServerSaysItRunsAsFailover() {
        #expect(AggregationNotice.text(chosen: .bond, effective: .failover) == "尚未设置聚合服务器，暂按主备运行")
        #expect(AggregationNotice.text(chosen: .bond, effective: .bond) == nil)
        #expect(AggregationNotice.text(chosen: .balance, effective: .balance) == nil)
        #expect(AggregationNotice.text(chosen: .failover, effective: .failover) == nil)
        #expect(AggregationNotice.text(chosen: .bond, effective: nil) == nil, "fewer than two links: the picker is disabled")
    }
}
