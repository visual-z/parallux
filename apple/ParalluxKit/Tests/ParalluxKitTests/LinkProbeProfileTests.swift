import Foundation
import Testing
@testable import ParalluxKit

@Suite struct LinkProbeProfileTests {
    @Test func theProbeProfileHasOneBoundDirectPerInterface() throws {
        #expect(LinkProbeProfile.make(interfaces: []) == nil)
        let text = try #require(LinkProbeProfile.make(interfaces: ["en0", "en7"]))
        let root = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let outbounds = try #require(root["outbounds"] as? [[String: Any]])
        let directs = outbounds.filter { $0["type"] as? String == "direct" && $0["bind_interface"] != nil }
        #expect(directs.map { $0["tag"] as? String } == ["probe-en0", "probe-en7"])
        #expect(directs.map { $0["bind_interface"] as? String } == ["en0", "en7"])
        let group = try #require(outbounds.first { $0["tag"] as? String == LinkProbeProfile.groupTag })
        #expect(group["type"] as? String == "urltest")
        #expect(group["outbounds"] as? [String] == ["probe-en0", "probe-en7"])
        #expect(group["url"] as? String == LinkProbeProfile.testURL)
        let inbounds = try #require(root["inbounds"] as? [[String: Any]])
        #expect(inbounds.first?["type"] as? String == "tun")
        #expect(inbounds.first?["auto_route"] as? Bool == true)
        #expect(root["dns"] != nil)
        let one = try #require(LinkProbeProfile.make(interfaces: ["en0"]))
        #expect(one.contains("\"probe-en0\""))
    }
}

extension LinkProbeProfileTests {
    /// core/pxbridge checks this fixture with libbox.CheckConfig; the
    /// generator must keep producing exactly it.
    @Test func theGeneratorMatchesTheFixtureLibboxChecks() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("core/pxbridge/testdata/probe-profile.json")
        let expected = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? NSDictionary
        let generated = try JSONSerialization.jsonObject(with: Data(#require(LinkProbeProfile.make(interfaces: ["en0", "en7"])).utf8)) as? NSDictionary
        #expect(expected != nil)
        #expect(generated == expected)
    }
}
