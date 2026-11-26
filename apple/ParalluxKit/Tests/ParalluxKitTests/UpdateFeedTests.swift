import Foundation
import Testing
@testable import ParalluxKit

@Suite struct UpdateFeedTests {
    @Test func updateFeedsResolveByChannel() {
        let stable = "https://example.com/appcast.xml"
        let beta = "https://example.com/appcast-beta.xml"
        let key = "Ae2oQLTcx89/a73XrpOt+IVvqdo+fMTjo3UKEm77VdA="
        #expect(UpdateFeed.resolve(channel: .stable, stable: stable, beta: beta, publicKey: key) == .feed(URL(string: stable)!))
        #expect(UpdateFeed.resolve(channel: .beta, stable: stable, beta: beta, publicKey: key) == .feed(URL(string: beta)!))
        #expect(UpdateFeed.resolve(channel: .beta, stable: stable, beta: nil, publicKey: key) == .feed(URL(string: stable)!), "no beta feed: stable")
        #expect(UpdateFeed.resolve(channel: .beta, stable: stable, beta: "", publicKey: key) == .feed(URL(string: stable)!), "empty beta feed: stable")
        #expect(UpdateFeed.resolve(channel: .stable, stable: "", beta: beta, publicKey: key) == .notConfigured, "no stable feed")
        #expect(UpdateFeed.resolve(channel: .stable, stable: nil, beta: nil, publicKey: key) == .notConfigured)
        #expect(UpdateFeed.resolve(channel: .stable, stable: stable, beta: nil, publicKey: "") == .notConfigured, "no key: nothing to verify against")
        #expect(UpdateFeed.resolve(channel: .stable, stable: stable, beta: nil, publicKey: nil) == .notConfigured)
        #expect(UpdateFeed.resolve(channel: .stable, stable: "$(PARALLUX_UPDATE_FEED)", beta: nil, publicKey: key) == .notConfigured, "unexpanded variable")
        #expect(UpdateFeed.resolve(channel: .stable, stable: "http://example.com/appcast.xml", beta: nil, publicKey: key) == .notConfigured, "updates only over https")
        #expect(UpdateFeed.resolve(channel: .beta, stable: stable, beta: "http://example.com/beta.xml", publicKey: key) == .feed(URL(string: stable)!), "an insecure beta feed is ignored")
    }
}
